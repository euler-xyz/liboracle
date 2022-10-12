// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/LibOracle.sol";
import "./StubOracle.sol";


contract EMA is Test {
    // Two EMAs run on the same data-set. One is updated periodically (with no price change)
    // and the other isn't. Their EMA and variances should closely match.

    function test_basic() public {
        StubOracle lo = new StubOracle(1);
        StubOracle lo2 = new StubOracle(1);

        skip(15);
        lo.test_doUpdate(500);
        lo2.test_doUpdate(500);

        for (uint i = 0; i < 2*60*2; i++) {
            skip(15);
            lo.test_doUpdate(500);
            //dumpShortEMA("LO1", lo);
            //dumpShortEMA("LO2", lo2);
        }
    }


    // stddev converges near the maximum possible: sqrt(274854262362*256) = 8388247.204552

    function test_maxVariance() public {
        StubOracle lo = new StubOracle(1);

        for (uint i = 0; i < 5000; i++) {
            skip(15);
            lo.test_doUpdate(i % 2 == 0 ? int24(-8388352) : int24(8388352));

            if (i > 3000) {
                LibOracle.OracleContext memory oc = lo.oracleLoadContext();
                LibOracle.OracleUpdateSet memory us = lo.oracleGetUpdateSet(oc);

                assert(us.shortVariance == 274854262362 || us.shortVariance == 274854277861);
            }
        }
    }

    function dumpShortEMA(string memory prefix, StubOracle lo) internal view {
        LibOracle.OracleContext memory oc = lo.oracleLoadContext();
        LibOracle.OracleUpdateSet memory us = lo.oracleGetUpdateSet(oc);
        console.log(prefix, "SHORTEMA", uint(int(us.shortMean) / 256), uint(us.shortVariance));
    }
}
