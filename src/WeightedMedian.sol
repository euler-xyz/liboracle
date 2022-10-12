// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// QuickSelect, modified to account for item weights
// Each item's weight is taken from its least-significant 16 bits
// arr.length and targetWeight must be > 0

library WeightedMedian  {
    function weightedMedian(uint[] memory arr, uint targetWeight, bytes32 randomSeed) internal pure returns (uint) {
        unchecked {
            uint weightAccum = 0;
            uint left = 0;
            uint right = (arr.length - 1) * 32;
            uint arrp;

            assembly {
                arrp := add(arr, 32)
            }

            while (true) {
                if (left == right) return memload(arrp, left);

                uint pivot;
                {
                    assembly {
                        mstore(0x00, randomSeed)
                        randomSeed := keccak256(0x00, 0x20)
                    }

                    pivot = memload(arrp, left + (((uint(randomSeed) % ((right - left) / 32))) * 32));
                }

                uint i = left - 32;
                uint j = right + 32;
                uint leftWeight = 0;

                while (true) {
                    i += 32;
                    while (true) {
                        uint w = memload(arrp, i);
                        if (w >= pivot) break;
                        leftWeight += w & 0xFFFF;
                        i += 32;
                    }

                    do j -= 32; while (memload(arrp, j) > pivot);

                    if (i >= j) {
                        if (i == j) leftWeight += memload(arrp, j) & 0xFFFF;
                        break;
                    }

                    leftWeight += memswap(arrp, i, j) & 0xFFFF;
                }

                if (weightAccum + leftWeight >= targetWeight) {
                    right = j;
                } else {
                    weightAccum += leftWeight;
                    left = j + 32;
                }
            }
        }

        assert(false);
        return 0;
    }

    // Array access without bounds checking

    function memload(uint arrp, uint i) private pure returns (uint ret) {
        assembly {
            ret := mload(add(arrp, i))
        }
    }

    // Swap two items in array without bounds checking, returns new element in i

    function memswap(uint arrp, uint i, uint j) private pure returns (uint output) {
        assembly {
            let iOffset := add(arrp, i)
            let jOffset := add(arrp, j)
            output := mload(jOffset)
            mstore(jOffset, mload(iOffset))
            mstore(iOffset, output)
        }
    }
}
