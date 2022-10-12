// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Math.sol";
import { LibOracleUtils as Utils } from "../src/LibOracleUtils.sol";
import "./WeightedMedian.sol";


contract LibOracle {
    // Constants

    uint internal constant EMA_WINDOW_SHORT = 30 * 60;
    uint internal constant EMA_WINDOW_LONG = 60 * 60 * 2;
    int internal constant EMA_EXTRA_SCALE = 256;

    uint private constant RING_BUFFER_UNINITIALISED = 0x0000_0000_0001_0000;
    uint private constant RING_BUFFER_INVALID       = 0x0001_0000_0000_0000;


    // Data structures

    struct OracleContext {
        // Current state (8)
        uint40 lastUpdate;
        int24 currTick;

        // Ring-buffer meta-data (6)
        uint16 ringCurr;
        uint16 ringSize;
        uint16 ringCapacity;

        // Short-term EMA (8)
        int24 shortMean;
        uint40 shortVariance;

        // Long-term EMA (8)
        int24 longMean;
        uint40 longVariance;

        // Extra (2)
        int16 tickAtStartOfBlock;
    }

    struct OracleUpdateSet {
        int24 shortMean;
        uint40 shortVariance;

        int24 longMean;
        uint40 longVariance;

        int16 tickAtStartOfBlock;
    }


    // Storage

    OracleContext private oracleContext;
    uint[8192] private ringBuffer;


    // Internal interface

    function oracleInit() internal {
        oracleContext.ringSize = oracleContext.ringCapacity = 8;
        ringBuffer[0] = RING_BUFFER_UNINITIALISED;
        oracleContext.lastUpdate = uint40(block.timestamp);
    }

    function oracleUpdate(OracleContext memory oc, OracleUpdateSet memory us, int24 newTick) internal {
        unchecked {
            if (newTick != oc.currTick) {
                (oc.shortMean, oc.shortVariance) = (us.shortMean, us.shortVariance);
                (oc.longMean, oc.longVariance) = (us.longMean, us.longVariance);

                uint elapsed = block.timestamp - oc.lastUpdate;

                if (elapsed != 0) {
                    if (oc.ringSize != oc.ringCapacity && oc.ringCurr == oc.ringSize - 1) oc.ringSize = oc.ringCapacity;
                    oc.ringCurr = (oc.ringCurr + 1) % oc.ringSize;
                    writeRing(oc.ringCurr, tickToSmallTick(oc.currTick), Utils.clampTime(elapsed));
                }

                oc.lastUpdate = uint40(block.timestamp);
                oc.currTick = newTick;
            }

            oracleContext = oc;
        }
    }

    function tickToSmallTick(int24 tick) internal pure returns (int16) {
        unchecked {
            return int16((tick + (tick > 0 ? EMA_EXTRA_SCALE/2 : -EMA_EXTRA_SCALE/2)) / EMA_EXTRA_SCALE);
        }
    }

    function smallTickToTick(int16 smallTick) internal pure returns (int24) {
        unchecked {
            return int24(smallTick * EMA_EXTRA_SCALE);
        }
    }


    // Public interface

    function extendRingBuffer(uint n) public {
        unchecked {
            require(n > 0 && n <= 65528, "out of ring buffer range");
            n = (n + 7) / 8;

            OracleContext memory oc = oracleContext;

            for (uint i = oc.ringCapacity / 8; i < n; ++i) {
                ringBuffer[i] = RING_BUFFER_UNINITIALISED;
                oc.ringCapacity += 8;
            }

            oracleContext = oc;
        }
    }

    function oracleLoadContext() public view returns (OracleContext memory) {
        return oracleContext;
    }

    function oracleGetUpdateSet(OracleContext memory oc) public view returns (OracleUpdateSet memory us) {
        unchecked {
            if (oc.lastUpdate != block.timestamp) {
                uint elapsed = block.timestamp - oc.lastUpdate;
                (us.shortMean, us.shortVariance) = updateEMA(elapsed, oc.currTick, oc.shortMean, oc.shortVariance, EMA_WINDOW_SHORT);
                (us.longMean, us.longVariance) = updateEMA(elapsed, oc.currTick, oc.longMean, oc.longVariance, EMA_WINDOW_LONG);
                us.tickAtStartOfBlock = tickToSmallTick(oc.currTick);
            } else {
                (us.shortMean, us.shortVariance) = (oc.shortMean, oc.shortVariance);
                (us.longMean, us.longVariance) = (oc.longMean, oc.longVariance);
                us.tickAtStartOfBlock = oc.tickAtStartOfBlock;
            }
        }
    }

    function oracleRead(uint desiredAge) public view returns (uint16, int24, int24) { // returns (actualAge, median, average)
        OracleContext memory oc = oracleContext;

        unchecked {
            (uint[] memory arr, uint actualAge, int tickAccum) = oracleReadRingBuffer(oc, desiredAge);

            bytes32 randomSeed = bytes32(uint(blockhash(block.number - 1)) ^ uint(uint160(msg.sender)) ^ block.timestamp);

            return (
                uint16(actualAge),
                smallTickToTick(Utils.unMemoryPackTick(WeightedMedian.weightedMedian(arr, (actualAge+1)/2, randomSeed))),
                int24(tickAccum / int(actualAge))
            );
        }
    }

    function oracleReadRingBuffer(OracleContext memory oc, uint desiredAge) public view returns (uint[] memory arr, uint actualAge, int tickAccum) {
        unchecked {
            require(desiredAge != 0 && desiredAge <= type(uint16).max, "desiredAge out of range");

            actualAge = 0;

            // Load ring buffer entries into memory

            {
                uint arrSize = 0;
                uint256 freeMemoryPointer;
                assembly {
                    arr := mload(0x40)
                    freeMemoryPointer := add(arr, 0x20)
                }

                // Populate first element in arr with current tick, if any time has elapsed since current tick was set

                {
                    uint duration = Utils.clampTime(block.timestamp - oc.lastUpdate);

                    int smallTick = tickToSmallTick(oc.currTick);

                    if (duration != 0) {
                        if (duration > desiredAge) duration = desiredAge;
                        actualAge += duration;

                        uint packed = Utils.memoryPackTick(smallTick, duration);

                        assembly {
                            mstore(freeMemoryPointer, packed)
                            freeMemoryPointer := add(freeMemoryPointer, 0x20)
                        }
                        ++arrSize;
                    }

                    tickAccum = smallTick * EMA_EXTRA_SCALE * int(duration);
                }

                // Continue populating elements until we have satisfied desiredAge

                {
                    uint _ringCurr = oc.ringCurr;
                    uint _ringSize = oc.ringSize;

                    uint i = _ringCurr;
                    uint cache = RING_BUFFER_INVALID;

                    while (actualAge != desiredAge) {
                        int tick;
                        uint duration;

                        {
                            if (cache == RING_BUFFER_INVALID) cache = ringBuffer[i / 8];
                            uint entry = cache >> (32 * (i % 8));
                            if (i % 8 == 0) cache = RING_BUFFER_INVALID;
                            tick = int(int16(uint16((entry >> 16) & 0xFFFF)));
                            duration = entry & 0xFFFF;
                        }

                        if (duration == 0) break; // uninitialised

                        if (actualAge + duration > desiredAge) duration = desiredAge - actualAge;
                        actualAge += duration;

                        uint packed = Utils.memoryPackTick(tick, duration);

                        assembly {
                            mstore(freeMemoryPointer, packed)
                            freeMemoryPointer := add(freeMemoryPointer, 0x20)
                        }
                        ++arrSize;

                        tickAccum += tick * EMA_EXTRA_SCALE * int(duration);

                        i = (i + _ringSize - 1) % _ringSize;
                        if (i == _ringCurr) break; // wrapped back around
                    }

                    assembly {
                        mstore(arr, arrSize)
                        mstore(0x40, freeMemoryPointer)
                    }
                }
            }
        }
    }


    // Private

    function updateEMA(uint elapsed, int24 currTick, int24 mean, uint40 variance, uint window) private pure returns (int24, uint40) {
        unchecked {
            int alpha;
            {
                int x = int(elapsed * 1e18 / window);
                alpha = x < 0.5e18 ? Utils.approxExpInvWad(x) : Math.expWad(-x);
            }

            int diff = int(currTick) - int(mean);
            int incr = (1e18 - alpha) * diff / 1e18;
            mean += int24(incr);
            variance = uint40(uint(alpha * (int(uint(variance)) + (diff * incr / EMA_EXTRA_SCALE)) / 1e18));

            return (mean, variance);
        }
    }

    function writeRing(uint index, int tick, uint duration) private {
        unchecked {
            uint packed = (uint(uint16(int16(tick))) << 16) | duration;

            uint shift = 32 * (index % 8);
            ringBuffer[index / 8] = (ringBuffer[index / 8] & ~(0xFFFFFFFF << shift))
                                    | (packed << shift);
        }
    }
}
