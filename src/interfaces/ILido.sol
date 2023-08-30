// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface ILido {
    function submit(address _referral) external payable returns (uint256);

    function requestWithdrawals(
        uint256[1] memory _amounts,
        address _owner
    ) external returns (uint256[] memory requestIds);
}
