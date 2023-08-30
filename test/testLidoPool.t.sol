// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {SoritesLidoPool} from "src/pools/SoritesLidoPool.sol";

contract SoritesLidoPoolTest is Test {
    function setUp() public {
        SoritesLidoPool pool = new SoritesLidoPool();
    }

    function test_PoolDeployment() public {}

    function test_userDeposit() public {}
}
