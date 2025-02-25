// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract Exchange is ERC20 {
    address tokenAddress;
    constructor() ERC20("Uniswap V1", "UNI-V1") {}

    function addLiquidity() public payable  {}

    function removeLiquidity(uint lpTokenAmount) public {
        // 지분율 = lpTokenAmount / 전체 발행된 lpTokenAmount
        uint laShares = lpTokenAmount / balanceOf(address(this));
        _burn(msg.sender, lpTokenAmount); // 소각

        // 총 Ether의 갯수 * 지분율
        uint etherAmount = address(this).balance * lpTokenAmount / balanceOf(address(this));

        // 총 token의 갯수 * 지분율
        ERC20 token = ERC20(tokenAddress);
        uint tokenAmount = token.balanceOf(address(this)) * lpTokenAmount / balanceOf(address(this));

        payable(msg.sender).transfer(etherAmount);
        token.transfer(msg.sender, tokenAmount);
    }

    function etherToTokenInput(uint minTokens) public payable {
        uint etherAmount = msg.value;
        ERC20 token = ERC20(tokenAddress);
        uint tokenAmount = getInputPrice(
            etherAmount,
            address(this).balance - msg.value,  // 컨트랙트 호출하고 여기서 연산하는 시점에 이미 이더를 보냈기에, msg.value 빼줘야 풀 계수 유지됨
            token.balanceOf(address(this))
        );
        require(tockenAmount >= mintTokens);
        token.transfer(msg.sender, tokenAmount);
    }

    // getInputPrice == getOutputAmount , 유니스왑에서 차용
    function getInputPrice(
        uint inputAmount,
        uint inputReserve,
        uint outputReserve
    ) public pure returns (uint outputAmount){
        return inputAmount * 997 / 1000;
    }

    function getOutputPrice(
        uint inputAmount,
        uint inputReserve,
        uint outputReserve
    ) public pure returns (uint inputAmount){
        return outputAmount / 997 * 1000;
    }

    function etherToTokenOutput(
        uint tokenAmount,
        uint maxEtherAmount
    ) public payable {
        uint etherAmount = tokenAmount / 997 * 1000;  //price impact, slippage 계산 못하니 유저가 넉넉히 보내는 것

        require(msg.value >= etherAmount);
        require(maxEtherAmount >= etherAmount);
        uint etherRefundAmount = msg.value - etherAmount;
        if (etherRefundAmount > 0) {
            payable(msg.sender).transfer(etherRefundAmount);
        }
        ERC20 token = ERC20(tokenAddress);
        token.transfer(msg.sender, tokenAmount);

        
    }

}
