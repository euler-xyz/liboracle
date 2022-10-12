// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Math.sol";

library LibOracleUtils {
    // (2/2) Padé Approximant of 1/e^x. In range [0..0.5] max error is .0044%.

    function approxExpInvWad(int x) internal pure returns (int) {
        unchecked {
            int a = (x * x) + 12e36;
            int b = x * 6e18;
            return (a - b) * 1e18 / (a + b);
        }
    }


    // Price/tick conversions

    function ratioToTick(uint a, uint b) internal pure returns (int24) {
        unchecked {
            int sign = 1;
            if (a < b) (a, b, sign) = (b, a, -1);
            return int24(sign * Math.lnWad(int(a * 1e18 / b)) / 10576909399089); // ln(1.000010576965334793)*1e18
        }
    }

    function tickToPriceWad(int24 tick) internal pure returns (uint) {
        unchecked {
            int output = Math.expWad(int(tick) * 88.722839111672999605e18 / 8388352); // ln(2**128)*1e18, MAX_TICK
            require(output != 0, "price can't fit in wad");
            return uint(output);
        }
    }


    // Saturate timestamp at 2**16 - 1

    function clampTime(uint t) internal pure returns (uint) {
        unchecked {
            return t > type(uint16).max ? uint(type(uint16).max) : t;
        }
    }


    // Pack/unpack a tick and duration into a uint

    function memoryPackTick(int tick, uint duration) internal pure returns (uint) {
        unchecked {
            return (uint(tick + 32768) << 16) | duration;
        }
    }

    function unMemoryPackTick(uint rec) internal pure returns (int16) {
        unchecked {
            return int16(int(rec >> 16) - 32768);
        }
    }
}
