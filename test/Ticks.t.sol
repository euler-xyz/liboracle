// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { LibOracleUtils as Utils } from "../src/LibOracleUtils.sol";


contract Ticks is Test {
    function test_ratioToTick() public {
        assertEq(Utils.ratioToTick(1e18, 1e18), 0);

        assertEq(Utils.ratioToTick(1e18, 2e18), -65534);
        assertEq(Utils.ratioToTick(2e18, 1e18), 65534);
        assertEq(Utils.ratioToTick(4e18, 1e18), 131068);

        assertEq(Utils.ratioToTick(2, 1), 65534);
        assertEq(Utils.ratioToTick(8, 4), 65534);

        assertEq(Utils.ratioToTick(1e18, 2**128 * 1e18), -8388352);
        assertEq(Utils.ratioToTick(2**128 * 1e18, 1e18), 8388352);
    }

    function test_tickToPriceWad() public {
        assertEq(Utils.tickToPriceWad(Utils.ratioToTick(1e18, 1e18)), 1e18);

        assertEq(Utils.tickToPriceWad(Utils.ratioToTick(1e18, 2e18)), 0.5e18);
        assertEq(Utils.tickToPriceWad(Utils.ratioToTick(2e18, 1e18)), 1.999999999999999999e18);

        vm.expectRevert("price can't fit in wad");
        Utils.tickToPriceWad(Utils.ratioToTick(1e18, 2**128 * 1e18));
        vm.expectRevert("price can't fit in wad");
        Utils.tickToPriceWad(Utils.ratioToTick(2**128 * 1e18, 1e18));
    }
}
