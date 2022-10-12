// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/LibOracle.sol";


contract StubOracle is LibOracle {
    constructor(uint16 ringCapacity) {
        oracleInit();
        extendRingBuffer(ringCapacity);
    }

    function test_oracleUpdate(OracleContext memory oc, OracleUpdateSet memory us, int16 newTick) external {
        oracleUpdate(oc, us, newTick);
    }

    function test_doUpdate(int24 newTick) public {
        LibOracle.OracleContext memory oc = oracleLoadContext();
        oracleUpdate(oc, oracleGetUpdateSet(oc), newTick);
    }

    function updateOracle(int24 newTick) public {
        test_doUpdate(newTick);
    }

    function getUpdateSet() external view returns (OracleUpdateSet memory) {
        LibOracle.OracleContext memory oc = oracleLoadContext();
        return oracleGetUpdateSet(oc);
    }
}
