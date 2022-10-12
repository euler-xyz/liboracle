// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/LibOracle.sol";
import "./StubOracle.sol";


contract RingBufferTest is Test {
    bytes32 seed;

    function setUp() public {
        genRandom(2);
    }

    function genRandom(uint range) internal returns (uint) {
        bytes32 value = seed;

        assembly {
            mstore(0x00, value)
            value := keccak256(0x00, 0x20)
        }

        seed = value;
        return uint(value) % range;
    }

    function test_reads() public {
        StubOracle lo = new StubOracle(144);

        for (uint i = 0; i < 10000; i++) {
            if (genRandom(100) < 5) {
                uint capacity = getCapacity(lo);
                if (capacity < 65528) lo.extendRingBuffer(capacity + 8);
            }

            uint duration = genRandom(60);
            if (duration < 5) duration = 0;
            int16 newTick = int16(int(genRandom(2000))) - 1000;

            lo.test_doUpdate(newTick);
            skip(duration);

            (uint16 actualAge, int24 median, int24 average) = lo.oracleRead(1800);

            // These DATA lines are for consumption by the test/processOracleTest.js script
            console.log(string(abi.encodePacked("DATA,",
                vm.toString(duration), ",",
                vm.toString(int(newTick)), ",",
                vm.toString(uint(actualAge)), ",",
                vm.toString(int(median)), ",",
                vm.toString(int(average))
            )));
        }
    }

    function test_resize() public {
        StubOracle lo = new StubOracle(1);

        assertRing(lo, 0, 8, 8);

        skipAndDoUpdate(lo, 15, 500);
        assertRing(lo, 1, 8, 8);

        // 9 rounds up to 16
        lo.extendRingBuffer(9);
        assertRing(lo, 1, 8, 16);

        // no-op if already extended
        lo.extendRingBuffer(16);
        assertRing(lo, 1, 8, 16);

        // Same price *doesn't* advance curr
        skipAndDoUpdate(lo, 15, 500);
        assertRing(lo, 1, 8, 16);

        // New price does
        skipAndDoUpdate(lo, 15, 501);
        assertRing(lo, 2, 8, 16);

        skipAndDoUpdate(lo, 15, 502);
        skipAndDoUpdate(lo, 15, 503);
        skipAndDoUpdate(lo, 15, 504);
        skipAndDoUpdate(lo, 15, 505);
        skipAndDoUpdate(lo, 15, 506);

        assertRing(lo, 7, 8, 16);

        // This update bumps size up to capacity
        skipAndDoUpdate(lo, 15, 507);
        assertRing(lo, 8, 16, 16);
    }

    function test_maxbuffer() public {
        StubOracle lo = new StubOracle(1);

        vm.expectRevert('out of ring buffer range');
        lo.extendRingBuffer(65529);

        lo.extendRingBuffer(65528);
        assertRing(lo, 0, 8, 65528);

        for (uint i = 0; i < 65528; i++) {
            skipAndDoUpdate(lo, 15, int16(int(i % 1000)));
        }

        assertRing(lo, 65527, 65528, 65528);

        // Final wrapping
        skipAndDoUpdate(lo, 15, -10);
        assertRing(lo, 0, 65528, 65528);
    }

    function assertRing(StubOracle lo, uint curr, uint size, uint capacity) internal {
        LibOracle.OracleContext memory oc = lo.oracleLoadContext();

        assertEq(oc.ringCurr, curr);
        assertEq(oc.ringSize, size);
        assertEq(oc.ringCapacity, capacity);
    }

    function getCapacity(StubOracle lo) internal view returns (uint) {
        LibOracle.OracleContext memory oc = lo.oracleLoadContext();
        return oc.ringCapacity;
    }

    function skipAndDoUpdate(StubOracle lo, uint secs, int16 newTick) internal {
        skip(secs);
        lo.test_doUpdate(newTick);
    }
}
