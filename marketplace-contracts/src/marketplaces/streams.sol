// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

// note each physical asset is represented by a tokenId within a fractional contract
// This contract supports rewards streaming towards multiple fractional assets, and multiple tokenIds within each fractional asset
// A single reward token is common to all staked assets

error PinlinkRewards_AmountTooLow();
error PinlinkRewards_AlreadyEnabled();
error PinlinkRewards_AssetNotEnabled();
error PinlinkRewards_DepositRewardsTooEarly();
error PinlinkRewards_AssetSupplyTooHigh();
error PinlinkRewards_AssetSupplyIsZero();
error PinlinkRewards_DrippingPeriodTooLong();
error PinlinkRewards_DrippingPeriodTooShort();

/// @title RewardsStreamer
/// @notice This struct is used to store the rewards data for each fractional token and each tokenId
struct RewardsStream {
    /// @notice global rewards per staked token, scaled up by PRECISION
    uint256 globalRewardsPerStakedTarget;
    /// @notice the totalSupply, which is static and cannot be modified
    uint256 assetSupply;
    /// @notice the amount that is being dripped
    uint256 deltaGlobalRewardsPerStaked;
    /// @notice timestamp when rewards were last deposited
    uint256 lastDepositTimestamp;
    /// @notice the current length of the dripping period
    uint256 drippingPeriod;
    // staked of each account in this physical asset
    mapping(address => uint256) stakedBalances;
    // Earned rewards that haven't been yet claimed
    mapping(address => uint256) pendingRewards;
    // claimed rewards of each account in this physical asset
    mapping(address => uint256) updatedRewardsPerStaked;
}

library StreamHandler {
    using StreamHandler for RewardsStream;

    uint256 constant PRECISION = 1e18;

    // The rewards are calculated dividing by the asset supply.
    // The larger the supply the larger the reminder, which is lost as rounding errors
    // with a supply of 1000, depositing 0.99$ will leave a max reminder of 0.0099999 $
    // (less than 1 cent lost in each rewards distribution)
    uint256 constant MAX_ASSET_SUPPLY = 1e4;

    // a minimum of 1 USDC deposited as rewards every time.
    uint256 constant MIN_REWARDS_DEPOSIT_AMOUNT = 1e6;

    // The dripping period is the period of time after which deposited rewards are fully dripped
    uint256 constant MIN_DRIPPING_PERIOD = 6 hours;
    uint256 constant MAX_DRIPPING_PERIOD = 15 days;

    function isEnabled(RewardsStream storage self) internal view returns (bool) {
        return self.assetSupply > 0;
    }

    function isDrippingPeriodFinished(RewardsStream storage self) internal view returns (bool) {
        return block.timestamp > self.lastDepositTimestamp + self.drippingPeriod;
    }

    function enableAsset(RewardsStream storage self, uint256 assetSupply, address receiver) internal {
        require(assetSupply > 0, PinlinkRewards_AssetSupplyIsZero());
        require(assetSupply < MAX_ASSET_SUPPLY, PinlinkRewards_AssetSupplyTooHigh());
        // At the beginning, all supply starts earing rewards for the receiver until purchased (admin account)
        self.updateRewards(receiver);
        self.stakedBalances[receiver] += assetSupply;
        // assetSupply is immutable so the following field cannot be modified ever again
        self.assetSupply = assetSupply;
    }

    function transferBalances(RewardsStream storage self, address from, address to, uint256 amount) internal {
        self.updateRewards(from);
        self.updateRewards(to);
        self.stakedBalances[from] -= amount;
        self.stakedBalances[to] += amount;
    }

    function claimRewards(RewardsStream storage self, address account) internal returns (uint256 claimed) {
        self.updateRewards(account);
        claimed = self.pendingRewards[account];
        delete self.pendingRewards[account];
    }

    function depositRewards(RewardsStream storage self, uint256 amount, uint256 drippingPeriod) internal {
        if (drippingPeriod > MAX_DRIPPING_PERIOD) revert PinlinkRewards_DrippingPeriodTooLong();
        if (drippingPeriod < MIN_DRIPPING_PERIOD) revert PinlinkRewards_DrippingPeriodTooShort();

        if (!self.isDrippingPeriodFinished()) revert PinlinkRewards_DepositRewardsTooEarly();
        if (!self.isEnabled()) revert PinlinkRewards_AssetNotEnabled();

        // This ensures rounding errors are negligible (less than 0.01$ per deposit)
        if (amount < MIN_REWARDS_DEPOSIT_AMOUNT) revert PinlinkRewards_AmountTooLow();

        // The number of fractions per asset is expected to be on the order of 100.
        // Thus, precision loss will usually be negligible (on the order of less than 100 wei)
        // Therefore, precision loss is deliberately ignored here to save gas
        uint256 delta = (amount * PRECISION) / self.assetSupply;
        /// The dripping mechanism is to avoid step jumps in rewards
        self.globalRewardsPerStakedTarget += delta;
        self.deltaGlobalRewardsPerStaked = delta;
        self.lastDepositTimestamp = block.timestamp;
        self.drippingPeriod = drippingPeriod;
    }

    /// @dev This function returns the global rewards per staked token,
    ///     accounting for a dripping factor to avoid step jumps
    /// @dev at deposit, this returns the previous globalRewardsPerStaked before depositing (no jump)
    /// @dev after drippingPeriod, this returns the target globalRewardsPerStakedTarget
    function globalRewardsPerStaked(RewardsStream storage self) internal view returns (uint256) {
        if (self.lastDepositTimestamp == 0) return 0;

        // safe subtraction as is always less or equal to block.timestamp
        uint256 timeSinceDeposit = block.timestamp - self.lastDepositTimestamp;

        uint256 _drippingDuration = self.drippingPeriod;
        // if the _drippingDuration has passed, then locked is 0
        // at deposit, locked has to be deltaGlobalRewardsPerStaked
        // during the _drippingDuration, locked is an interpolation between deltaGlobalRewardsPerStaked and 0
        uint256 locked = (timeSinceDeposit > _drippingDuration)
            ? 0
            : self.deltaGlobalRewardsPerStaked * (_drippingDuration - (timeSinceDeposit)) / _drippingDuration;

        /// return the target after _drippingDuration, and before that, an interpolation between last and new target
        return self.globalRewardsPerStakedTarget - locked;
    }

    function updateRewards(RewardsStream storage self, address account) internal {
        uint256 globalPerStaked = self.globalRewardsPerStaked();
        self.pendingRewards[account] += self._pendingRewardsSinceLastUpdate(globalPerStaked, account);
        self.updatedRewardsPerStaked[account] = globalPerStaked;
    }

    /// @dev output is is reward tokens (not scaled by PRECISION)
    function getPendingRewards(RewardsStream storage self, address account) internal view returns (uint256) {
        uint256 globalPerStaked = self.globalRewardsPerStaked();
        return self.pendingRewards[account] + self._pendingRewardsSinceLastUpdate(globalPerStaked, account);
    }

    /// @dev output is is reward tokens (not scaled by PRECISION)
    function _pendingRewardsSinceLastUpdate(RewardsStream storage self, uint256 globalPerStaked, address account)
        internal
        view
        returns (uint256)
    {
        // this can't underflow, because this always holds: `globalRewardsPerStaked() >= updatedRewardsPerStaked[account]`
        return (self.stakedBalances[account] * (globalPerStaked - self.updatedRewardsPerStaked[account])) / PRECISION;
    }
}
