#!/usr/bin/env python3
"""
uart_host.py — Host script for AES-128 Image Encryption on Basys 3

Modes:
  encrypt: Load a 128x128 grayscale image, send raw pixels to FPGA via UART
  decrypt: Send trigger, receive 16384 decrypted bytes, reconstruct image

Usage:
  python uart_host.py --mode encrypt --port COM3 --image input.png
  python uart_host.py --mode decrypt --port COM3 --output decrypted.png

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
BAUD_RATE    = 115200
UART_TIMEOUT = 30   # seconds


def encrypt_mode(port: str, image_path: str) -> None:
    """Load image, resize to 128x128 grayscale, send raw bytes to FPGA."""
    print(f"[ENCRYPT] Loading image: {image_path}")
    img = cv2.imread(image_path, cv2.IMREAD_GRAYSCALE)
    if img is None:
        print(f"ERROR: Cannot read image '{image_path}'")
        sys.exit(1)

    img = cv2.resize(img, (IMG_WIDTH, IMG_HEIGHT))
    raw_bytes = img.flatten().tobytes()
    assert len(raw_bytes) == TOTAL_BYTES, f"Expected {TOTAL_BYTES} bytes, got {len(raw_bytes)}"

    print(f"[ENCRYPT] Image size: {img.shape}, total bytes: {len(raw_bytes)}")
    print(f"[ENCRYPT] Opening serial port: {port} @ {BAUD_RATE} baud")

    ser = serial.Serial(port, BAUD_RATE, timeout=UART_TIMEOUT)
    time.sleep(2)  # wait for FPGA to be ready after port open

    print(f"[ENCRYPT] Sending {TOTAL_BYTES} bytes...")
    bytes_sent = 0
    chunk_size = 256  # send in chunks with small delays for reliability
    for i in range(0, TOTAL_BYTES, chunk_size):
        chunk = raw_bytes[i:i + chunk_size]
        ser.write(chunk)
        bytes_sent += len(chunk)
        # Small delay between chunks to avoid UART FIFO overflow
        time.sleep(0.01)
        if bytes_sent % 4096 == 0:
            print(f"  Sent {bytes_sent}/{TOTAL_BYTES} bytes...")

    print(f"[ENCRYPT] Done! {bytes_sent} bytes sent to FPGA.")
    print("[ENCRYPT] Image is now encrypted and stored in BRAM.")
    print("[ENCRYPT] Flip SW0 to decrypt mode and press btnR to read back.")
    ser.close()


def decrypt_mode(port: str, output_path: str) -> None:
    """Receive 16384 decrypted bytes from FPGA, reconstruct image."""
    print(f"[DECRYPT] Opening serial port: {port} @ {BAUD_RATE} baud")

    ser = serial.Serial(port, BAUD_RATE, timeout=UART_TIMEOUT)
    time.sleep(2)

    print(f"[DECRYPT] Waiting for {TOTAL_BYTES} bytes from FPGA...")
    print("[DECRYPT] Make sure SW0 is HIGH (decrypt) and press btnR on the board.")

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

    ser.close()

    print(f"[DECRYPT] Received {len(rx_data)} bytes. Reconstructing image...")
    img = np.frombuffer(rx_data, dtype=np.uint8).reshape(IMG_HEIGHT, IMG_WIDTH)
    cv2.imwrite(output_path, img)
    print(f"[DECRYPT] Decrypted image saved to: {output_path}")

    # Display the image
    try:
        cv2.imshow("Decrypted Image", img)
        print("[DECRYPT] Press any key to close the image window.")
        cv2.waitKey(0)
        cv2.destroyAllWindows()
    except Exception:
        pass  # headless environment


def main():
    parser = argparse.ArgumentParser(
        description="AES-128 Image Encryption Host — Basys 3 FPGA"
    )
    parser.add_argument(
        "--mode", choices=["encrypt", "decrypt"], required=True,
        help="encrypt: send image to FPGA | decrypt: receive image from FPGA"
    )
    parser.add_argument(
        "--port", type=str, required=True,
        help="Serial port (e.g., COM3 on Windows, /dev/ttyUSB0 on Linux)"
    )
    parser.add_argument(
        "--image", type=str, default="input.png",
        help="Input image path (encrypt mode only)"
    )
    parser.add_argument(
        "--output", type=str, default="decrypted.png",
        help="Output image path (decrypt mode only)"
    )

    args = parser.parse_args()

    if args.mode == "encrypt":
        encrypt_mode(args.port, args.image)
    else:
        decrypt_mode(args.port, args.output)


if __name__ == "__main__":
    main()
