// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

contract FactoryProxy {
    
    address public logic;    
    address public owner;        
    
    event LogicUpdated(address newLogic);
    event OwnerChanged(address newOwner);
    
    constructor(address _logic) {
        logic = _logic;
        owner = msg.sender;
    }
    
    // 단순한 접근 제어
    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }
    
    // 로직 컨트랙트 업데이트
    function updateLogic(address newLogic) external onlyOwner {
        require(newLogic != address(0), "zero address");
        logic = newLogic;
        emit LogicUpdated(newLogic);
    }
    
    // 소유자 변경
    function changeOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero address");
        owner = newOwner;
        emit OwnerChanged(newOwner);
    }
    
    // fallback
    fallback() external payable {
        address _logic = logic;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), _logic, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
    
    receive() external payable {
    }
}