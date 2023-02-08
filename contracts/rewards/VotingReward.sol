// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Reward} from "./Reward.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";

/// @title Base voting reward contract for distribution of rewards by token id
///        on a weekly basis
abstract contract VotingReward is Reward {
    constructor(address _voter, address[] memory _rewards) Reward(_voter) {
        for (uint256 i; i < _rewards.length; i++) {
            if (_rewards[i] != address(0)) {
                isReward[_rewards[i]] = true;
                rewards.push(_rewards[i]);
            }
        }

        authorized = _voter;
    }

    /// @inheritdoc Reward
    function getReward(uint256 tokenId, address[] memory tokens) external override nonReentrant {
        address sender = _msgSender();
        require(
            IVotingEscrow(ve).isApprovedOrOwner(sender, tokenId) || sender == voter,
            "VotingReward: unpermissioned"
        );

        address _owner = IVotingEscrow(ve).ownerOf(tokenId);
        _getReward(_owner, tokenId, tokens);
    }

    /// @inheritdoc Reward
    function notifyRewardAmount(address token, uint256 amount) external virtual override {}
}