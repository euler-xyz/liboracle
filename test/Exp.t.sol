// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { LibOracleUtils as Utils } from "../src/LibOracleUtils.sol";
import "../src/Math.sol";


contract Exp is Test {
    function test_approxExpInvWad() public {
        assertEq(Utils.approxExpInvWad(0), 1e18);
        assertEq(Utils.approxExpInvWad(0.1e18), 0.904837430610626486e18);
        assertEq(Utils.approxExpInvWad(0.5e18), 0.606557377049180327e18);
        assertEq(Utils.approxExpInvWad(1e18),   0.368421052631578947e18);
        assertEq(Utils.approxExpInvWad(1.5e18), 0.225806451612903225e18);
    }

    function test_expWad() public {
        assertEq(Math.expWad(0), 1e18);
        assertEq(Math.expWad(-0.1e18), 0.904837418035959573e18);
        assertEq(Math.expWad(-0.5e18), 0.606530659712633423e18);
        assertEq(Math.expWad(-1e18),   0.367879441171442321e18);
        assertEq(Math.expWad(-1.5e18), 0.223130160148429828e18);
    }
}
