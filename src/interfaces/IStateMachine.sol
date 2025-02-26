// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IStateMachine {
    enum State { 
        Inactive,    // 초기 상태
        Active,      // 활성화 상태
        Paused,      // 일시 중지 상태
        Terminated   // 종료 상태
    }
    
    event StateChanged(State indexed previousState, State indexed newState);
    
    function getState() external view returns (State);
    function setState(State newState) external;
    function isValidStateTransition(State currentState, State newState) external pure returns (bool);
}