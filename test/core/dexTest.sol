// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "src/core/ERC20Mintable.sol";
import "src/core/Exchange.sol";
import "src/core/Factory.sol";
import "src/core/FactoryProxy.sol";
import "src/interfaces/IStateMachine.sol";

contract UUPSFactoryTest is Test {
    ERC20Mintable token;
    Exchange exchange;
    Factory factoryLogic; // Factory 로직 컨트랙트
    Factory factory;      // Proxy를 통한 Factory 호출 (Factory 타입)
    FactoryProxy proxy;
    address user = address(1);

    function setUp() public {
        vm.deal(user, 2 ether);

        // ERC20 토큰 배포 및 민팅
        token = new ERC20Mintable("Erwin Token", "ET");
        token.mint(address(this), 100 * 1e18);
        token.mint(user, 100 * 1e18);

        // Factory 로직 컨트랙트 배포
        factoryLogic = new Factory();

        // UUPS 프록시 초기화를 위해 Factory.initialize()를 호출하는 calldata 준비
        bytes memory initData = abi.encodeWithSignature("initialize()");
        // UUPS 프록시 배포 (logic = factoryLogic, 초기화 calldata 전달)
        proxy = new FactoryProxy(address(factoryLogic), initData);

        // 프록시 주소를 Factory 타입으로 캐스팅하여 사용
        factory = Factory(address(proxy));

        // 이미 setUp에서 createExchange를 호출하지 않도록 주의:
        // testProxyPattern에서는 다른 토큰 주소를 사용하여 createExchange 테스트 진행
        address exchangeAddr = factory.createExchange(address(token));
        exchange = Exchange(payable(exchangeAddr));
    }

    // ERC20Mintable의 mint 및 transfer 기능 테스트
    function testERC20Mintable() public {
        uint initialBalance = token.balanceOf(user);
        vm.prank(user);
        token.mint(user, 1000 * 1e18);
        uint newBalance = token.balanceOf(user);
        assertEq(newBalance, initialBalance + 1000 * 1e18);
    }

    // Exchange의 유동성 추가(addLiquidity) 테스트
    function testAddLiquidity() public {
        uint tokenAmount = 5 * 1e18;
        vm.startPrank(user);
        token.approve(address(exchange), tokenAmount);
        uint lpTokens = exchange.addLiquidity{value: 0.01 ether}(tokenAmount, tokenAmount);
        vm.stopPrank();
        uint lpBalance = exchange.balanceOf(user);
        assertEq(lpBalance, lpTokens);
    }

    // Exchange의 유동성 제거(removeLiquidity) 테스트
    function testRemoveLiquidity() public {
        uint tokenAmount = 5 * 1e18;
        vm.startPrank(user);
        token.approve(address(exchange), tokenAmount);
        uint lpTokens = exchange.addLiquidity{value: 0.01 ether}(tokenAmount, tokenAmount);
        (uint ethAmount, uint tokenReceived) = exchange.removeLiquidity(lpTokens);
        vm.stopPrank();
        uint lpBalance = exchange.balanceOf(user);
        assertEq(lpBalance, 0);
        assertGt(ethAmount, 0);
        assertGt(tokenReceived, 0);
    }

    // CPMM 기반 가격 함수 및 수수료 계산 테스트
    function testCPMMPrice() public {
        uint tokenAmount = 10 * 1e18;
        vm.startPrank(user);
        token.approve(address(exchange), tokenAmount);
        uint lpTokens = exchange.addLiquidity{value: 0.1 ether}(tokenAmount, tokenAmount);
        vm.stopPrank();
        
        uint inputAmount = 0.01 ether;
        uint outputPrice = exchange.getInputPrice(
            inputAmount,
            address(exchange).balance - inputAmount, // 실제 잔액에서 최근 입금을 차감
            token.balanceOf(address(exchange))
        );
        assertGt(outputPrice, 0);
        
        uint desiredOutput = 1 * 1e18;
        uint inputPrice = exchange.getOutputPrice(
            desiredOutput,
            address(exchange).balance - inputAmount,
            token.balanceOf(address(exchange))
        );
        assertGt(inputPrice, 0);
    }

    // 이더를 토큰으로 교환하는 etherToTokenOutput 테스트 (환불 확인)
    function testEtherToTokenOutput() public {
        uint tokenAmount = 10 * 1e18;
        vm.startPrank(user);
        token.approve(address(exchange), tokenAmount);
        exchange.addLiquidity{value: 0.1 ether}(tokenAmount, tokenAmount);
        
        uint tokensDesired = 0.1 * 1e18;
        uint maxEther = 0.01 ether;     
        uint ethSold = exchange.etherToTokenOutput{value: maxEther}(tokensDesired, maxEther);
        vm.stopPrank();
        
        assertLt(ethSold, maxEther);
    }

    // 토큰을 이더로 교환하는 tokenToEtherInput 테스트 (Pull over Push)
    function testTokenToEther() public {
        uint tokenAmount = 10 * 1e18;
        vm.startPrank(user);
        token.approve(address(exchange), tokenAmount);
        uint lpTokens = exchange.addLiquidity{value: 0.1 ether}(tokenAmount, tokenAmount);
        
        uint tokensSold = 1 * 1e18;
        token.approve(address(exchange), tokensSold);
        uint ethBought = exchange.tokenToEtherInput(tokensSold, 0);
        vm.stopPrank();
        assertGt(ethBought, 0);
    }

    // Factory의 Multicall 패턴 테스트
    function testMulticall() public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(factory.setState.selector, IStateMachine.State.Paused);
        data[1] = abi.encodeWithSelector(factory.EmergencyStop.selector);
        
        bytes[] memory results = factory.multicall(data);
        IStateMachine.State state = factory.getState();
        assertEq(uint(state), uint(IStateMachine.State.Paused));
        bool emergencyStopStatus = factory.emergencyStop();
        assertEq(emergencyStopStatus, true);
    }

    // UUPS Proxy 테스트: 프록시를 통해 Factory의 함수 호출 및 업그레이드 동작 확인
    function testProxyPattern() public {
        // 기존 setUp()에서 Exchange가 생성되었으므로, 여기서는 새로운 더미 토큰을 사용
        address dummyToken = address(0x123);
        address proxyExchange = factory.createExchange(dummyToken);
        require(proxyExchange != address(0), "Exchange creation failed");
        address proxyExchangeFromGet = factory.getExchange(dummyToken);
        assertEq(proxyExchangeFromGet, proxyExchange, "Exchange addresses do not match");
        
        // UUPS 업그레이드 테스트:
        // 새로운 Factory 로직 컨트랙트 배포 (동일 코드)
        Factory newFactoryLogic = new Factory();
        // admin은 setUp에서 initialize()를 통해 address(this)로 설정됨
        factory.upgradeTo(address(newFactoryLogic));
        // proxiableUUID 테스트
        bytes32 uuid = factory.proxiableUUID();
        bytes32 expectedUUID = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        assertEq(uuid, expectedUUID);
    }

    // Exchange의 State Machine 기능 테스트
    function testStateMachineExchange() public {
        IStateMachine.State state = exchange.getState();
        assertEq(uint(state), uint(IStateMachine.State.Active));

        vm.prank(address(factory));
        exchange.setState(IStateMachine.State.Paused);
        state = exchange.getState();
        assertEq(uint(state), uint(IStateMachine.State.Paused));

        vm.prank(address(factory));
        vm.expectRevert("INVALID_TRANSITION");
        exchange.setState(IStateMachine.State.Inactive);
    }

    // Factory의 State Machine 기능 테스트 (admin 권한)
    function testStateMachineFactory() public {
        IStateMachine.State state = factory.getState();
        assertEq(uint(state), uint(IStateMachine.State.Active));

        vm.prank(address(this));
        factory.setState(IStateMachine.State.Paused);
        state = factory.getState();
        assertEq(uint(state), uint(IStateMachine.State.Paused));
    }

    // Exchange의 Emergency Stop 기능 테스트 (Factory만 호출 가능)
    function testEmergencyStopExchange() public {
        vm.prank(address(factory));
        exchange.EmergencyStop();
        bool emergencyStopStatus = exchange.emergencyStop();
        assertEq(emergencyStopStatus, true);
    }
}
