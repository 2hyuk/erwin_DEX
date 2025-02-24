// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TokenA is ERC20 {
    
    constructor() ERC20("TokenA", "A") {
        _mint(msg.sender, 50 * 10)
    }

}

contract Exchange is ERC20 {
    // Ether <> A Token Exchange
    address public tokenAddress;  // = 0x...

    constructor(address _tokenAddress) ERC20("Uniswap LP", "UNI-LP") {
        tokenAddress = _tokenAddress;
    }

    function addLiquidity() public payable {
        // LP 사용자로부터 이더, 토큰을 받음
        uint etherAmount = msg.value;
        uint tokenAmount = etherAmount;
        TokenA tokenContract = TokenA(tokenAddress);
        tokenContract.transferFrom(msg.sender, address(this), tokenAmount);
        // LP 사용자에게 받은 만큼의 LP 토큰을 민팅함.
        _mint(msg.sender, tokenAmount);
    }

    function removeLiquidity(uint lpTokenAmount) public {
        // 1. LP토큰을 burn한다
        _burn(msg.sender, lpTokenAmount);
        uint etherAmount = lpTokenAmount;
        payable(msg.sender).transfer(etherAmount);
        TokenA tokenContract = TokenA(tokenAddress);
        tokenContract.transfer(msg.sender, tokenAmount);
        // 2. 지분만큼 이더, 토큰을 반환한다.
    }

    function etherToTokenSwap() public payable{
        uint etherAmount = msg.value;
        //CSMM: ehterAmount + tokenAmont = k
        uint tokenAmount = etherAmount;
        TokenA tokenContract = TokenA(tokenAddress);
        tokenContract.transfer(msg.sender, tokenAmount);
    }

    function tokenToEtherSwap(uint tokenAmount) {
        TokenA tokenContract = TokenA(tokenAddress);
        tokenContract.transferFrom(msg.sender, address(this), tokenAmount);
        uint etherAmount = tokenAmount;
        payable(msg.sender).tranasfer(etherAmount);
    }
}

