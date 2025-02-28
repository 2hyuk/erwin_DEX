// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./Exchange.sol";
import "@interfaces/IStateMachine.sol";

contract Factory is IStateMachine {
    event NewExchange(
        address indexed token,
        address indexed exchange
    );
    
    uint public tokenCount;
    mapping (address tokenAddress => address exchangeAddress) internal tokenToExchange;
    mapping (address exchangeAddress => address tokenAddress) internal exchangeToToken;
    mapping (uint256 exchangeId => address tokenAddress) internal idToToken;
    
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
    
    constructor() {
        admin = msg.sender;
        currentState = State.Active; // 생성 시 활성화 상태로 시작
        initialized = true;
    }
    // Factory뿐만 아니라 프록시 스토리지에도 Active 상태 초기화 되게끔 수정(추가)
    function initialize() external {
        require(!initialized, "AlREADY_INITIALIZED");
        admin = msg.sender;
        currentState = State.Active;
        initialized = true;
    }
    
    function createExchange(address tokenAddress) public whenActive returns (address exchangeAddress) {
        // Checks 검증
        require(tokenAddress != address(0), "ZERO_ADDRESS");
        require(tokenToExchange[tokenAddress] == address(0), "EXCHANGE_EXISTS");
        
        // Effects 상태 변경
        uint tokenId = tokenCount + 1;
        tokenCount = tokenId;
        idToToken[tokenId] = tokenAddress;
        
        // Interactions 외부 호출
        Exchange exchange = new Exchange(tokenAddress);
        exchangeAddress = address(exchange);
        
        // 새로 생긴 Exchange 상태를 Factory의 상태와 동기화시킴
        exchange.initializeState();
        
        // 새로운 Exchange 만들고 매핑 업데이트
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
        // 상태 전이 규칙 정의
        if (_currentState == State.Inactive) {
            return _newState == State.Active;
        } else if (_currentState == State.Active) {
            return _newState == State.Paused || _newState == State.Terminated;
        } else if (_currentState == State.Paused) {
            return _newState == State.Active || _newState == State.Terminated;
        } else if (_currentState == State.Terminated) {
            return false; // 종료 상태에서는 다른 상태로 전환 불가
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