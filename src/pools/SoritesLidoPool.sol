// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ILido} from "../interfaces/ILido.sol";

contract SoritesLidoPool is ERC20("SOR-LIDO", "Sorites Lido Share") {
    address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant LIDO_ADDRESS = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    constructor() {}

    function deposit() public payable {
        //Receives eth
        require(msg.value > 0, "must send ether");
        _deposit(msg.value);
    }

    function depositWETH(uint amount) public {
        require(
            IERC20(WETH_ADDRESS).transferFrom(
                msg.sender,
                address(this),
                amount
            ),
            "transfer failed"
        );
        _deposit(amount);
    }

    function _deposit(uint amount) internal {
        // Deposits to LIDO and mints SOR-LP
        (bool sent, bytes memory data) = LIDO_ADDRESS.call{value: amount}("");
        require(sent, "lido deposit failed");
        _mint(msg.sender, amount);
    }

    function _withdraw(uint amount) internal {
        uint[1] memory amounts = [amount];
        ILido(LIDO_ADDRESS).requestWithdrawals(amounts, address(this));
    }

    // function withdraw(uint amount) public {
    //     require(balanceOf(msg.sender) >= amount, "Not enough staked");
    //     (bool sent, bytes memory data) = msg.sender.call{value: amount}("");
    //     require(sent, "Failed to send Ether");
    //     _burn(msg.sender, amount);
    // }
}
