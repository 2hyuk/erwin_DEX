// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mintable is ERC20 {
    uint256 private constant INITIAL_SUPPLY = 100 * (100 ** 18); // 초기 민팅 수량 설정

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, INITIAL_SUPPLY); // 초기 민팅
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}