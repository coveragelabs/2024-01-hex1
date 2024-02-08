// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../../src/HexOneStaking.sol";

contract HexOneStakingWrap is HexOneStaking {
    constructor(address _hexToken, address _hexitToken, uint16 _hexDistRate, uint16 _hexitDistRate)
        HexOneStaking(_hexToken, _hexitToken, _hexDistRate, _hexitDistRate)
    {}

    function getPoolInfoStakeAmount(address user, address token) public view returns (uint256) {
        StakeInfo storage stakeInfo = stakingInfos[user][token];
        return stakeInfo.stakedAmount;
    }
}
