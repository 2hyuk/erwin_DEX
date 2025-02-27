// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@interfaces/IStateMachine.sol";

contract Exchange is ERC20, IStateMachine {
    address public tokenAddress;
    address public factory;
    uint public constant MIN_FEE = 0;
    uint public constant MAX_FEE = 30;
    
    // State Machine 구현
    State public currentState = State.Inactive;
    
    // Emergency Stop 구현
    bool public emergencyStop;

    event TokenPurchase(address indexed buyer, uint256 indexed etherSold, uint256 indexed tokensBought);
    event EtherPurchase(address indexed buyer, uint256 indexed tokensSold, uint256 indexed etherBought);
    event AddLiquidity(address indexed provider, uint256 indexed etherAmount, uint256 indexed tokenAmount);
    event RemoveLiquidity(address indexed provider, uint256 indexed etherAmount, uint256 indexed tokenAmount);
    
    constructor(
        address _tokenAddress
    ) ERC20("UPSIDE", "UP") {
        tokenAddress = _tokenAddress;
        factory = msg.sender;
        currentState = State.Inactive;
    }
    
    // Factory에서만 호출 가능한 초기화 함수
    function initializeState() external {
        require(msg.sender == factory, "ONLY_FACTORY");
        require(currentState == State.Inactive, "ALREADY_INITIALIZED");
        currentState = State.Active;
    }
    
    modifier whenActive() {
        require(currentState == State.Active, "NOT_ACTIVE");
        require(!emergencyStop, "EMERGENCY_STOP_ACTIVE");
        _;
    }
    
    modifier onlyFactory() {
        require(msg.sender == factory, "ONLY_FACTORY");
        _;
    }

    function addLiquidity(
        uint minLpTokenAmount,
        uint maxTokenAmount
    ) public payable whenActive returns (uint lpTokenAmount) {
        
        require(msg.value > 0, "ZERO_ETH");
        
        ERC20 token = ERC20(tokenAddress);
        uint totalLiquidity = totalSupply();

        if (totalLiquidity == 0) {
            
            require(maxTokenAmount > 0, "ZERO_TOKENS");
            
            uint etherAmount = msg.value;
            uint tokenAmount = maxTokenAmount;
            lpTokenAmount = etherAmount;
            
            bool success = token.transferFrom(msg.sender, address(this), tokenAmount);
            require(success, "TRANSFER_FAILED");

            _mint(msg.sender, lpTokenAmount);
            
            emit AddLiquidity(msg.sender, etherAmount, tokenAmount);
            return lpTokenAmount;
        } else {
        
            uint etherReserve = address(this).balance - msg.value;
            uint tokenReserve = token.balanceOf(address(this));
            
            lpTokenAmount = totalLiquidity * msg.value / etherReserve;
            uint tokenAmount = tokenReserve * msg.value / etherReserve;
            
            require(lpTokenAmount >= minLpTokenAmount, "INSUFFICIENT_LP_TOKENS");
            require(maxTokenAmount >= tokenAmount, "EXCESSIVE_TOKEN_AMOUNT");

            bool success = token.transferFrom(msg.sender, address(this), tokenAmount);
            require(success, "TRANSFER_FAILED");

            _mint(msg.sender, lpTokenAmount);
            
            emit AddLiquidity(msg.sender, msg.value, tokenAmount);
            return lpTokenAmount;
        }
    }

    function removeLiquidity(
        uint lpTokenAmount
    ) public whenActive returns (uint etherAmount, uint tokenAmount) {
        require(lpTokenAmount > 0, "ZERO_AMOUNT");
        require(balanceOf(msg.sender) >= lpTokenAmount, "INSUFFICIENT_BALANCE");
        
        uint totalLiquidity = totalSupply();
        ERC20 token = ERC20(tokenAddress);
        
        etherAmount = address(this).balance * lpTokenAmount / totalLiquidity;
        tokenAmount = token.balanceOf(address(this)) * lpTokenAmount / totalLiquidity;
        _burn(msg.sender, lpTokenAmount);
        
        // ETH 전송
        (bool success, ) = payable(msg.sender).call{value: etherAmount}("");
        require(success, "ETH_TRANSFER_FAILED");
        
        // 토큰 전송
        bool tokenSuccess = token.transfer(msg.sender, tokenAmount);
        require(tokenSuccess, "TOKEN_TRANSFER_FAILED");
        
        emit RemoveLiquidity(msg.sender, etherAmount, tokenAmount);
        return (etherAmount, tokenAmount);
    }

    // 랜덤 수수료 계산 함수
    function getRandomFee() public view returns (uint) {
        bytes32 randomHash = keccak256(
            abi.encodePacked(
                blockhash(block.number - 1),
                block.timestamp,
                msg.sender,
                address(this)
            )
        );
        // 0부터 MAX_FEE까지의 랜덤값 생성
        return uint(randomHash) % (MAX_FEE +1);
    }

    /// @notice Calculate the output amount of a trade given the input amount, input reserve, and output reserve
    /// @dev This function implements the "x * y = k" formula for constant product automated market makers
    /// @param inputAmount The amount of input token being supplied
    /// @param inputReserve The total reserve of input token
    /// @param outputReserve The total reserve of output token
    /// @return outputAmount The amount of output token that will be received

    function getInputPrice(
        uint inputAmount,   // A, A값이 고정되어 있을 때 B의 값 찾는 것
        uint inputReserve,  // X
        uint outputReserve  // Y
    ) public view returns (uint outputAmount) {
        
        require(inputAmount > 0, "ZERO_INPUT");
        require(inputReserve > 0 && outputReserve > 0, "INSUFFICIENT_RESERVES");
        
        // CPMM
        // (X * Y) = (X + A)(Y - B) = k
        // XY = XY - XB + AY - AB
        // AY = XB + AB
        // AY = B(A + X)
        // AY / (A + X) = B

        uint numerator = inputAmount * outputReserve;
        uint denominator = inputAmount + inputReserve;
        uint outputAmountWithFee = numerator / denominator;

        // 랜덤 수수료 적용
        uint randomFee = getRandomFee();
        outputAmount = outputAmountWithFee * (1000 - randomFee) / 1000;

        
    }

    /// @notice Calculate the input amount required for a trade given the output amount, input reserve, and output reserve
    /// @dev This function implements the "x * y = k" formula for constant product automated market makers
    /// @param outputAmount The amount of output token desired
    /// @param inputReserve The total reserve of input token
    /// @param outputReserve The total reserve of output token
    /// @return inputAmount The amount of input token that needs to be provided

    function getOutputPrice(
    uint outputAmount,  // B,  B값이 고정되어 있을 때 A의 값 찾는 것
    uint inputReserve,  // X
    uint outputReserve  // Y
) public view returns (uint inputAmount) {
    
    require(outputAmount > 0, "ZERO_OUTPUT");
    require(inputReserve > 0 && outputReserve > 0, "INSUFFICIENT_RESERVES");
    require(outputAmount < outputReserve, "INSUFFICIENT_OUTPUT_RESERVE");
    
    // CPMM
    uint numerator = inputReserve * outputAmount;
    uint denominator = outputReserve - outputAmount;
    uint inputAmountWithoutFee = numerator / denominator;

    uint randomFee = getRandomFee();
    inputAmount = inputAmountWithoutFee * 1000 / (1000 - randomFee);
    
    }
    event FeeApplied(uint fee);

    function etherToTokenInput(
        uint minTokens
    ) public payable whenActive returns (uint tokensBought) {
        require(msg.value > 0, "ZERO_ETH");
        
        // Price Discovery
        uint etherSold = msg.value;
        ERC20 token = ERC20(tokenAddress);
        tokensBought = getInputPrice(
            etherSold, 
            address(this).balance - msg.value, // 컨트랙트 호출하고 여기서 연산하는 시점에 이미 이더를 보냈기에, msg.value 빼줘야 풀 계수 유지됨
            token.balanceOf(address(this))
        );

        require(tokensBought >= minTokens, "INSUFFICIENT_OUTPUT");
        
        bool success = token.transfer(msg.sender, tokensBought);
        require(success, "TRANSFER_FAILED");

        emit TokenPurchase(msg.sender, etherSold, tokensBought);
        return tokensBought;
    }

    function etherToTokenOutput(
        uint tokensBought,
        uint maxEther
    ) public payable whenActive returns (uint etherSold) {
        
        require(tokensBought > 0, "ZERO_TOKENS");
        
        // Price Discovery
        ERC20 token = ERC20(tokenAddress);
        etherSold = getOutputPrice(
            tokensBought,
            address(this).balance - msg.value,
            token.balanceOf(address(this))
        );

        // Effects
        require(msg.value >= etherSold, "INSUFFICIENT_ETH");
        require(maxEther >= etherSold, "EXCESSIVE_ETH_AMOUNT");

        // Refund (Pull )
        uint etherRefundAmount = msg.value - etherSold;
        if (etherRefundAmount > 0) {
            (bool success, ) = payable(msg.sender).call{value: etherRefundAmount}("");
            require(success, "ETH_REFUND_FAILED");
        }

        // Token Transfer
        bool tokenSuccess = token.transfer(msg.sender, tokensBought);
        require(tokenSuccess, "TRANSFER_FAILED");

        emit TokenPurchase(msg.sender, etherSold, tokensBought);
        return etherSold;
    }

    function tokenToEtherInput(
        uint tokensSold,
        uint minEther
    ) public whenActive returns (uint etherBought) {
        
        require(tokensSold > 0, "ZERO_TOKENS");
        
        // Price Discovery
        ERC20 token = ERC20(tokenAddress);
        etherBought = getInputPrice(
            tokensSold,
            token.balanceOf(address(this)),
            address(this).balance
        );

        require(etherBought >= minEther, "INSUFFICIENT_OUTPUT");

        // 토큰 전송 (Pull)
        bool tokenSuccess = token.transferFrom(msg.sender, address(this), tokensSold);
        require(tokenSuccess, "TRANSFER_FAILED");
        
        // ETH 전송
        (bool success, ) = payable(msg.sender).call{value: etherBought}("");
        require(success, "ETH_TRANSFER_FAILED");

        emit EtherPurchase(msg.sender, tokensSold, etherBought);
        return etherBought;
    }

    function tokenToEtherOutput(
        uint etherBought,
        uint maxTokens
    ) public whenActive returns (uint tokensSold) {
    
        require(etherBought > 0, "ZERO_ETH");
        require(etherBought < address(this).balance, "INSUFFICIENT_ETH_RESERVES");
        
        // Price Discovery
        ERC20 token = ERC20(tokenAddress);
        tokensSold = getOutputPrice(
            etherBought,
            token.balanceOf(address(this)),
            address(this).balance
        );

        require(maxTokens >= tokensSold, "EXCESSIVE_TOKEN_AMOUNT");

        // 토큰 전송 (Pull over Push pattern)
        bool tokenSuccess = token.transferFrom(msg.sender, address(this), tokensSold);
        require(tokenSuccess, "TRANSFER_FAILED");
        
        // ETH 전송
        (bool success, ) = payable(msg.sender).call{value: etherBought}("");
        require(success, "ETH_TRANSFER_FAILED");

        emit EtherPurchase(msg.sender, tokensSold, etherBought);
        return tokensSold;
    }
    
    // State Machine 함수
    function getState() external view override returns (State) {
        return currentState;
    }
    
    function setState(State newState) external override onlyFactory {
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
    function EmergencyStop() external onlyFactory {
        emergencyStop = !emergencyStop;
    }
    
    // ETH 수신
    receive() external payable {
        // ETH 입금 허용
    }
}