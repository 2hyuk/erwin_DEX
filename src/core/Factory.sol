// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./Exchange.sol";
import "@interfaces/IStateMachine.sol";

contract Factory is IStateMachine {
    event NewExchange(address indexed token, address indexed exchange);
    event Upgraded(address newImplementation);

    uint public tokenCount;
    mapping (address => address) internal tokenToExchange;
    mapping (address => address) internal exchangeToToken;
    mapping (uint256 => address) internal idToToken;
    
    // State Machine 구현
    State public currentState = State.Inactive;
    
    // Emergency Stop 구현
    bool public emergencyStop;
    
    // Admin address
    address public admin;
    
    modifier onlyAdmin() {
        require(msg.sender == admin, "ONLY_ADMIN");
        _;
    }
    
    modifier whenActive() {
        require(currentState == State.Active, "NOT_ACTIVE");
        require(!emergencyStop, "EMERGENCY_STOP_ACTIVE");
        _;
    }

    bool public initialized;
    
    // UUPS: EIP-1967 Implementation Slot
    // keccak256("eip1967.proxy.implementation") - 1
    bytes32 internal constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    
    constructor() {
        admin = msg.sender;
        currentState = State.Active; // 생성 시 활성화 상태로 시작
        // 생성자에서는 proxy 환경에서는 storage에 기록되지 않으므로 초기화를 여기서 진행하지 않음
    }
    
    // UUPS: proxiableUUID 함수
    function proxiableUUID() external pure returns (bytes32) {
        return _IMPLEMENTATION_SLOT;
    }
    
    // UUPS: 업그레이드 함수 (admin만 호출 가능)
    function upgradeTo(address newImplementation) external onlyAdmin {
        require(newImplementation != address(0), "ZERO_ADDRESS");
        _upgradeTo(newImplementation);
        emit Upgraded(newImplementation);
    }
    
    function _upgradeTo(address newImplementation) internal {
        assembly {
            sstore(_IMPLEMENTATION_SLOT, newImplementation)
        }
    }
    
    // initialize 함수 (프록시 배포 후 1회 호출)
    function initialize() external {
        require(!initialized, "ALREADY_INITIALIZED");
        admin = msg.sender;  // 여기서 admin을 초기화 (proxy를 통해 호출되므로 caller가 admin이 됨)
        currentState = State.Active;
        initialized = true;
    }
    
    function createExchange(address tokenAddress) public whenActive returns (address exchangeAddress) {
        require(tokenAddress != address(0), "ZERO_ADDRESS");
        require(tokenToExchange[tokenAddress] == address(0), "EXCHANGE_EXISTS");
        
        uint tokenId = tokenCount + 1;
        tokenCount = tokenId;
        idToToken[tokenId] = tokenAddress;
        
        Exchange exchange = new Exchange(tokenAddress);
        exchangeAddress = address(exchange);
        
        exchange.initializeState();
        
        tokenToExchange[tokenAddress] = exchangeAddress;
        exchangeToToken[exchangeAddress] = tokenAddress;
        
        emit NewExchange(tokenAddress, exchangeAddress);
        return exchangeAddress;
    }
    
    function getExchange(address tokenAddress) public view returns (address exchangeAddress) {
        exchangeAddress = tokenToExchange[tokenAddress];
        return exchangeAddress;
    }
    
    function getToken(address exchangeAddress) public view returns (address tokenAddress) {
        tokenAddress = exchangeToToken[exchangeAddress];
        return tokenAddress;
    }
    
    function getTokenWithId(uint256 tokenId) public view returns (address tokenAddress) {
        tokenAddress = idToToken[tokenId];
        return tokenAddress;
    }
    
    // State Machine 함수
    function getState() external view override returns (State) {
        return currentState;
    }
    
    function setState(State newState) external override onlyAdmin {
        require(isValidStateTransition(currentState, newState), "INVALID_TRANSITION");
        State previousState = currentState;
        currentState = newState;
        emit StateChanged(previousState, newState);
    }
    
    function isValidStateTransition(State _currentState, State _newState) public pure override returns (bool) {
        if (_currentState == State.Inactive) {
            return _newState == State.Active;
        } else if (_currentState == State.Active) {
            return _newState == State.Paused || _newState == State.Terminated;
        } else if (_currentState == State.Paused) {
            return _newState == State.Active || _newState == State.Terminated;
        } else if (_currentState == State.Terminated) {
            return false;
        }
        return false;
    }
    
    // Emergency Stop 함수
    function EmergencyStop() external onlyAdmin {
        emergencyStop = !emergencyStop;
    }
    
    // Admin 
    function setAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "ZERO_ADDRESS");
        admin = newAdmin;
    }
    
    // Multicall 
    function multicall(bytes[] calldata data) external returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            require(success, "MULTICALL_FAILED");
            results[i] = result;
        }
        return results;
    }
}
