// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.36;

import {Test} from "forge-std/Test.sol";
import {FidelityPoints} from "../src/FidelityPoints.sol";

contract FidelityPointsTest is Test {
    FidelityPoints public fidelityPoints;

    address admin = address(this);
    address user = makeAddr("user");

    function setUp() public {
        fidelityPoints = new FidelityPoints(10);
    }

    function test_SetPointValue_AsAdmin() public {
        vm.prank(admin);
        fidelityPoints.setPointValue(20);
        assertEq(fidelityPoints.pointValue(), 20);
    }

    function test_SetPointValue_RevertWhen_NotAdmin() public {
        vm.prank(user);
        vm.expectRevert("Only admin!");
        fidelityPoints.setPointValue(20);

        assertEq(fidelityPoints.pointValue(), 10);
    }
}
