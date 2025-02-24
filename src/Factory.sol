// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

//Factory
// product(v1: exchange, v2: pair)

contract Exchange {
    uint public number;
    constructor(uint _number) {
        number = _number;
    }
}


contract Factory {
    function createExchange(uint number) pubic {
        new Exchange(1234);
    }
    
   
}

