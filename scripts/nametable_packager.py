import sys
import os
from enum import Enum


class TILE(Enum):
  BRICKS = 7
  BRICKS_INV = 9
  CUBE = 39
  CUBE_INV = 41

tile_to_idx_map = {
    TILE.BRICKS.value: 0,
    TILE.BRICKS_INV.value: 1,
    TILE.CUBE.value: 2,
    TILE.CUBE_INV.value: 3
}

def main():
  # Assume the binary file name is passed as the first argument
  binary_file_name = sys.argv[1]
  binary_file_size = os.stat(binary_file_name).st_size
  bytes = read_bytes(binary_file_name, binary_file_size)
  packaged_bytes = bytearray(package_bytes(bytes))
  write_bytes("output.bin", packaged_bytes)


def read_bytes(file_name, file_size) -> bytearray:
  with open(file_name, "rb") as f:
    file_bytes = f.read(file_size)
  return bytearray(file_bytes)


def combine_bytes(bytes):
  # Ensure all values are in the range 0-3, fitting in 2 bits
  # No need for a mask here as it's assumed they are already 0-3
  for idx, b in enumerate(bytes):
    bytes[idx] = tile_to_idx_map.get(b, 0)
  combined_byte = (bytes[0] << 6) | (bytes[1] << 4) | (
      bytes[2] << 2) | bytes[3]

  return combined_byte

def package_bytes(bytes):
  width = 32  # Assuming width of the data in bytes
  chunk_size = 4  # Processing 4x4 chunks

  packaged_byte_list = []

  # Iterate through each 4x4 chunk
  for row in range(0, 30,
                   chunk_size):  # Adjust the range if your height varies
    for col in range(0, width, chunk_size):
      i = (row * width) + col

      # Extract the first byte of each 2x2 region within the 4x4 chunk
      first_bytes = [
          bytes[i],  # Top-left 2x2 region
          bytes[i + 2],  # Top-right 2x2 region
          bytes[i + (width * 2)],  # Bottom-left 2x2 region
          bytes[i + (width * 2) + 2]  # Bottom-right 2x2 region
      ]

      # Combine the first bytes into a single byte
      # print(f"Packagin {first_bytes}")
      packaged_byte = combine_bytes(first_bytes)
      # print(f"Packaged byte: {format(packaged_byte, '#010b')}")
      # Append the packaged byte to the list
      packaged_byte_list.append(packaged_byte)

  return packaged_byte_list

def write_bytes(file_name, bytes):
  with open(file_name, "wb") as f:
    f.write(bytes)


if __name__ == "__main__":
  main()
