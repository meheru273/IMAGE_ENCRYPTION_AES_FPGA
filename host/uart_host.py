#!/usr/bin/env python3
"""
uart_host.py — Host script for AES-128 Image Encryption on Basys 3

Modes:
  encrypt        (Mode 1): Send key + image → receive encrypted image
  decrypt        (Mode 2): Send key + ciphertext → receive plaintext image
  retrieve       (Mode 3): Send key only → receive encrypted image (or 0xFF error)
  decrypt_stored (Mode 4): Send key only → receive decrypted image from stored BRAM

Usage:
  python uart_host.py --mode encrypt --port COM3 --image input.png --key 2b7e...3c
  python uart_host.py --mode decrypt --port COM3 --input encrypted.bin --key 2b7e...3c
  python uart_host.py --mode retrieve --port COM3 --key 2b7e...3c --output retrieved.png
  python uart_host.py --mode decrypt_stored --port COM3 --key 2b7e...3c --output decrypted.png

Requirements:
  pip install pyserial opencv-python numpy
"""

import argparse
import sys
import time
import numpy as np

try:
    import serial
except ImportError:
    print("ERROR: pyserial not installed. Run: pip install pyserial")
    sys.exit(1)

try:
    import cv2
except ImportError:
    print("ERROR: opencv-python not installed. Run: pip install opencv-python")
    sys.exit(1)


# ──────────────────────────────────────────────────────────────────────
# Constants
# ──────────────────────────────────────────────────────────────────────
IMG_WIDTH    = 128
IMG_HEIGHT   = 128
TOTAL_BYTES  = IMG_WIDTH * IMG_HEIGHT   # 16384
KEY_BYTES    = 16
BAUD_RATE    = 115200
UART_TIMEOUT = 30   # seconds


# ──────────────────────────────────────────────────────────────────────
# Helper functions
# ──────────────────────────────────────────────────────────────────────
def open_and_sync(port: str, mode_name: str, sw_desc: str) -> serial.Serial:
    """Open serial port, flush buffers, and prompt user to press btnR."""
    print(f"[{mode_name}] Opening serial port: {port} @ {BAUD_RATE} baud")
    ser = serial.Serial(port, BAUD_RATE, timeout=UART_TIMEOUT)
    time.sleep(0.5)  # let port settle
    ser.reset_input_buffer()
    ser.reset_output_buffer()
    print(f"")
    print(f"  ┌──────────────────────────────────────────────────────┐")
    print(f"  │  Set switches: {sw_desc:<39s}│")
    print(f"  │  Then press btnR on the Basys 3 board.              │")
    print(f"  │  After pressing btnR, press Enter here to continue. │")
    print(f"  └──────────────────────────────────────────────────────┘")
    print(f"")
    input("  >>> Press Enter after pressing btnR... ")
    ser.reset_input_buffer()  # flush any noise from button press
    time.sleep(0.1)  # small settle time
    return ser


def validate_key(key_hex: str) -> bytes:
    """Validate and convert a 32-character hex string to 16 bytes."""
    key_hex = key_hex.strip()
    if len(key_hex) != 32:
        print(f"ERROR: Key must be exactly 32 hex characters, got {len(key_hex)}")
        sys.exit(1)
    try:
        key_bytes = bytes.fromhex(key_hex)
    except ValueError:
        print("ERROR: Key contains invalid hex characters")
        sys.exit(1)
    return key_bytes


def send_key(ser: serial.Serial, key_bytes: bytes) -> None:
    """Send 16-byte AES key over UART."""
    assert len(key_bytes) == KEY_BYTES
    print(f"[KEY] Sending 16-byte AES key: {key_bytes.hex()}")
    ser.write(key_bytes)
    ser.flush()
    time.sleep(0.1)  # allow FPGA to process key bytes


def send_image_data(ser: serial.Serial, raw_bytes: bytes) -> None:
    """Send 16384 image bytes over UART in chunks."""
    assert len(raw_bytes) == TOTAL_BYTES
    print(f"[TX] Sending {TOTAL_BYTES} bytes...")
    bytes_sent = 0
    chunk_size = 256
    for i in range(0, TOTAL_BYTES, chunk_size):
        chunk = raw_bytes[i:i + chunk_size]
        ser.write(chunk)
        bytes_sent += len(chunk)
        time.sleep(0.01)
        if bytes_sent % 4096 == 0:
            print(f"  Sent {bytes_sent}/{TOTAL_BYTES} bytes...")
    ser.flush()
    print(f"[TX] Done! {bytes_sent} bytes sent.")


def receive_image_data(ser: serial.Serial) -> bytes:
    """Receive 16384 bytes from FPGA."""
    print(f"[RX] Waiting for {TOTAL_BYTES} bytes from FPGA...")
    rx_data = b''
    start_time = time.time()
    while len(rx_data) < TOTAL_BYTES:
        remaining = TOTAL_BYTES - len(rx_data)
        chunk = ser.read(remaining)
        if chunk:
            rx_data += chunk
            if len(rx_data) % 4096 == 0 or len(rx_data) == TOTAL_BYTES:
                print(f"  Received {len(rx_data)}/{TOTAL_BYTES} bytes...")
        if time.time() - start_time > UART_TIMEOUT:
            print(f"ERROR: Timeout! Only received {len(rx_data)}/{TOTAL_BYTES} bytes")
            ser.close()
            sys.exit(1)
    print(f"[RX] Received all {len(rx_data)} bytes.")
    return rx_data


def save_and_display_image(data: bytes, output_path: str, title: str = "Image") -> None:
    """Reconstruct 128x128 grayscale image and save."""
    img = np.frombuffer(data, dtype=np.uint8).reshape(IMG_HEIGHT, IMG_WIDTH)
    cv2.imwrite(output_path, img)
    print(f"[SAVE] {title} saved to: {output_path}")
    try:
        cv2.imshow(title, img)
        print(f"[DISPLAY] Press any key to close the '{title}' window.")
        cv2.waitKey(0)
        cv2.destroyAllWindows()
    except Exception:
        pass  # headless environment


# ──────────────────────────────────────────────────────────────────────
# Mode implementations
# ──────────────────────────────────────────────────────────────────────
def mode_encrypt(port: str, key_hex: str, image_path: str,
                 encrypted_output: str) -> None:
    """Mode 1: Full encrypt — send key + image, receive encrypted image."""
    key_bytes = validate_key(key_hex)

    print(f"[MODE 1 - ENCRYPT] Loading image: {image_path}")
    img = cv2.imread(image_path, cv2.IMREAD_GRAYSCALE)
    if img is None:
        print(f"ERROR: Cannot read image '{image_path}'")
        sys.exit(1)

    img = cv2.resize(img, (IMG_WIDTH, IMG_HEIGHT))
    raw_bytes = img.flatten().tobytes()
    assert len(raw_bytes) == TOTAL_BYTES

    print(f"[MODE 1] Image size: {img.shape}, total bytes: {len(raw_bytes)}")

    ser = open_and_sync(port, "MODE 1", "SW0=DOWN, SW1=DOWN")

    # Step 1: Send key
    send_key(ser, key_bytes)

    # Step 2: Send plaintext image
    send_image_data(ser, raw_bytes)

    # Step 3: Receive encrypted image back
    print("[MODE 1] Waiting for encrypted image from FPGA...")
    encrypted_data = receive_image_data(ser)
    ser.close()

    # Save encrypted image (will look like noise)
    save_and_display_image(encrypted_data, encrypted_output,
                           "Encrypted Image (noise)")

    # Also display the original for comparison
    try:
        cv2.imshow("Original Image", img)
        print("[DISPLAY] Press any key to close.")
        cv2.waitKey(0)
        cv2.destroyAllWindows()
    except Exception:
        pass

    print("[MODE 1] Encryption complete. Encrypted image + key stored on FPGA.")


def mode_decrypt(port: str, key_hex: str, input_path: str,
                 output_path: str) -> None:
    """Mode 2: Full decrypt — send key + ciphertext, receive plaintext."""
    key_bytes = validate_key(key_hex)

    print(f"[MODE 2 - DECRYPT] Loading encrypted data: {input_path}")
    # Read the encrypted image file as raw bytes
    enc_img = cv2.imread(input_path, cv2.IMREAD_GRAYSCALE)
    if enc_img is None:
        print(f"ERROR: Cannot read image '{input_path}'")
        sys.exit(1)

    enc_img = cv2.resize(enc_img, (IMG_WIDTH, IMG_HEIGHT))
    enc_bytes = enc_img.flatten().tobytes()
    assert len(enc_bytes) == TOTAL_BYTES

    ser = open_and_sync(port, "MODE 2", "SW0=UP, SW1=DOWN")

    # Step 1: Send key
    send_key(ser, key_bytes)

    # Step 2: Send ciphertext
    send_image_data(ser, enc_bytes)

    # Step 3: Receive decrypted image
    print("[MODE 2] Waiting for decrypted image from FPGA...")
    decrypted_data = receive_image_data(ser)
    ser.close()

    save_and_display_image(decrypted_data, output_path, "Decrypted Image")
    print("[MODE 2] Decryption complete.")


def mode_retrieve(port: str, key_hex: str, output_path: str) -> None:
    """Mode 3: Key-only retrieve — send key, receive encrypted image or error."""
    key_bytes = validate_key(key_hex)

    ser = open_and_sync(port, "MODE 3", "SW0=DOWN, SW1=UP")

    # Step 1: Send key
    send_key(ser, key_bytes)

    # Step 2: Wait for response — either 16384 bytes or 1 byte (0xFF)
    print("[MODE 3] Waiting for FPGA response...")
    start_time = time.time()

    # Read first byte with a timeout
    first_byte = ser.read(1)
    if not first_byte:
        print("ERROR: No response from FPGA (timeout)")
        ser.close()
        sys.exit(1)

    if first_byte == b'\xff':
        print("[MODE 3] Key mismatch — access denied (received 0xFF)")
        ser.close()
        return

    # First byte is part of the image data — continue reading
    rx_data = first_byte
    while len(rx_data) < TOTAL_BYTES:
        remaining = TOTAL_BYTES - len(rx_data)
        chunk = ser.read(remaining)
        if chunk:
            rx_data += chunk
            if len(rx_data) % 4096 == 0 or len(rx_data) == TOTAL_BYTES:
                print(f"  Received {len(rx_data)}/{TOTAL_BYTES} bytes...")
        if time.time() - start_time > UART_TIMEOUT:
            print(f"ERROR: Timeout! Only received {len(rx_data)}/{TOTAL_BYTES} bytes")
            ser.close()
            sys.exit(1)

    ser.close()
    print(f"[MODE 3] Received {len(rx_data)} bytes of encrypted data.")

    save_and_display_image(rx_data, output_path, "Retrieved Encrypted Image")
    print("[MODE 3] Retrieval complete.")


def mode_decrypt_stored(port: str, key_hex: str, output_path: str) -> None:
    """Mode 4: Key-only decrypt — send key, receive decrypted image from stored BRAM."""
    key_bytes = validate_key(key_hex)

    ser = open_and_sync(port, "MODE 4", "SW0=UP, SW1=UP")

    # Step 1: Send key
    send_key(ser, key_bytes)

    # Step 2: Receive decrypted image
    print("[MODE 4] Waiting for decrypted image from FPGA...")
    decrypted_data = receive_image_data(ser)
    ser.close()

    save_and_display_image(decrypted_data, output_path, "Decrypted Stored Image")
    print("[MODE 4] Decryption of stored data complete.")


# ──────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(
        description="AES-128 Image Encryption Host — Basys 3 FPGA (4-mode)"
    )
    parser.add_argument(
        "--mode",
        choices=["encrypt", "decrypt", "retrieve", "decrypt_stored"],
        required=True,
        help="Operation mode: encrypt (1), decrypt (2), retrieve (3), decrypt_stored (4)"
    )
    parser.add_argument(
        "--port", type=str, required=True,
        help="Serial port (e.g., COM3 on Windows, /dev/ttyUSB0 on Linux)"
    )
    parser.add_argument(
        "--key", type=str, required=True,
        help="32-character hex AES-128 key (e.g., 2b7e151628aed2a6abf7158809cf4f3c)"
    )
    parser.add_argument(
        "--image", type=str, default="input.png",
        help="Input image path (encrypt mode only)"
    )
    parser.add_argument(
        "--input", type=str, default="encrypted.png",
        help="Encrypted image input path (decrypt mode only)"
    )
    parser.add_argument(
        "--output", type=str, default="decrypted.png",
        help="Output image path (decrypt/retrieve/decrypt_stored modes)"
    )
    parser.add_argument(
        "--encrypted_output", type=str, default="encrypted.png",
        help="Encrypted output image path (encrypt mode only)"
    )

    args = parser.parse_args()

    if args.mode == "encrypt":
        mode_encrypt(args.port, args.key, args.image, args.encrypted_output)
    elif args.mode == "decrypt":
        mode_decrypt(args.port, args.key, args.input, args.output)
    elif args.mode == "retrieve":
        mode_retrieve(args.port, args.key, args.output)
    elif args.mode == "decrypt_stored":
        mode_decrypt_stored(args.port, args.key, args.output)


if __name__ == "__main__":
    main()
