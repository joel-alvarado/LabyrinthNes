import os
import sys
from enum import Enum


class TILE(Enum):
    BRICKS = 0x07
    BRICKS_INV = 0x29
    CUBE = 0x09
    CUBE_INV = 0x27
    ENTRANCE = 0x5D
    EXIT = 0x5E


tile_to_idx_map = {
    TILE.BRICKS.value: 0,
    TILE.BRICKS_INV.value: 1,
    TILE.CUBE.value: 2,
    TILE.CUBE_INV.value: 3,
    TILE.ENTRANCE.value: 0,
    TILE.EXIT.value: 0,
}


def main():
    # Assume the binary file name is passed as the first argument
    binary_file_name = sys.argv[1]
    binary_file_size = os.stat(binary_file_name).st_size
    bytes = read_bytes(binary_file_name, binary_file_size)
    attributes = extract_attributes_from_bytes(bytes)
    packaged_bytes = bytearray(package_bytes(bytes))
    stage_data = extract_stage_data_from_bytes(bytes)
    write_bytes(binary_file_name.replace(".bin", "_packaged.bin"), packaged_bytes)
    write_bytes(binary_file_name.replace(".bin", "_attributes.bin"), attributes)
    write_bytes(
        binary_file_name.replace(".bin", "_stage_data.bin"), bytearray(stage_data)
    )


def read_bytes(file_name, file_size) -> bytearray:
    with open(file_name, "rb") as f:
        file_bytes = f.read(file_size)
    return bytearray(file_bytes)


def extract_attributes_from_bytes(bytes):
    # Return last 64 bytes
    attribute_bytes = bytes[-64:]
    return bytearray(attribute_bytes)


def extract_stage_data_from_bytes(bytes):
    # Iterates through odd rows and extracts left byte of each 2x2 region
    start_stage_coords = (0, 0)
    end_stage_coords = (0, 0)
    for row in range(0, 30, 2):
        for col in range(0, 32, 2):
            base_idx = (row * 32) + col
            x, y = base_idx % 32, base_idx // 32
            if bytes[base_idx] == TILE.ENTRANCE.value:
                start_stage_coords = (x * 8 + 1, y * 8)
            elif bytes[base_idx] == TILE.EXIT.value:
                end_stage_coords = (x * 8 + 1, y * 8)
    stage_data = [
        start_stage_coords[0],
        start_stage_coords[1],
        end_stage_coords[0],
        end_stage_coords[1],
    ]
    print(stage_data)
    return stage_data


def combine_bytes(bytes):
    # Ensure all values are in the range 0-3, fitting in 2 bits
    # No need for a mask here as it's assumed they are already 0-3
    for idx, b in enumerate(bytes):
        bytes[idx] = tile_to_idx_map.get(b, 0)
    combined_byte = (bytes[0] << 6) | (bytes[1] << 4) | (bytes[2] << 2) | bytes[3]

    return combined_byte


def package_bytes(bytes):
    width = 32  # Assuming the width of the data in 'tiles', not bytes
    row_tiles = width // 2  # Number of 2x2 tile regions per row

    packaged_byte_list = []

    # Iterate through each 2x2 region in the 8x2 row
    for row in range(0, 30, 2):  # Iterate over rows, two at a time
        for col in range(
            0, row_tiles, 4
        ):  # Iterate over columns, four 2x2 regions at a time
            # Calculate the index for the top-left tile of each 2x2 region
            base_idx = (row * width) + (col * 2)

            # Extract the first tile of each 2x2 region in the 8x2 area
            # and convert them to their 2-bit representations
            first_bytes = [
                bytes[base_idx],
                bytes[base_idx + 2],
                bytes[base_idx + 4],
                bytes[base_idx + 6],
            ]

            packaged_byte = combine_bytes(first_bytes)

            # Append the packaged byte to the list
            packaged_byte_list.append(packaged_byte)
    return packaged_byte_list


def write_bytes(file_name, bytes):
    print(f"Writing {len(bytes)} bytes to {file_name}")
    with open(file_name, "wb") as f:
        f.write(bytes)


if __name__ == "__main__":
    main()
