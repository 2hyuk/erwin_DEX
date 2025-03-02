// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

contract FactoryProxy {
    // EIP-1967: implementation slot (keccak256("eip1967.proxy.implementation") - 1)
    bytes32 private constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    
    /// @notice 프록시 배포 시 로직 컨트랙트 주소와 초기화 calldata(_data)를 받아 설정합니다.
    constructor(address _logic, bytes memory _data) payable {
        require(_logic != address(0), "logic is 0");
        assembly {
            sstore(_IMPLEMENTATION_SLOT, _logic)
        }
        if (_data.length > 0) {
            (bool success, ) = _logic.delegatecall(_data);
            require(success, "Initialization failed");
        }
    }
    
    fallback() external payable {
        _delegate();
    }
    
    receive() external payable {
        _delegate();
    }
    
    function _delegate() private {
        assembly {
            let impl := sload(_IMPLEMENTATION_SLOT)
            if iszero(impl) {
                revert(0, 0)
            }
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
    
    /// @notice 슬롯에 저장된 로직 주소를 반환합니다.
    function getImplementation() public view returns (address impl) {
        assembly {
            impl := sload(_IMPLEMENTATION_SLOT)
        }
    }
}
