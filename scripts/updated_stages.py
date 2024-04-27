import nametable_packager


def main():
    stage_files = [
        "assets/nametables/stage_one/stage_one_left.bin",
        "assets/nametables/stage_one/stage_one_right.bin",
        "assets/nametables/stage_two/stage_two_left.bin",
        "assets/nametables/stage_two/stage_two_right.bin",
    ]

    for f in stage_files:
        nametable_packager.handle_nametable_bin(f)


if __name__ == "__main__":
    main()
