# PinLink: RWA-Tokenized DePIN Marketplace contest details

- Join [Sherlock Discord](https://discord.gg/MABEWyASkp)
- Submit findings using the **Issues** page in your private contest repo (label issues as **Medium** or **High**)
- [Read for more details](https://docs.sherlock.xyz/audits/watsons)

# Q&A

### Q: On what chains are the smart contracts going to be deployed?
Ethereum mainnet only. 
___

### Q: If you are integrating tokens, are you allowing only whitelisted tokens to work with the codebase or any complying with the standard? Are they assumed to have certain properties, e.g. be non-reentrant? Are there any types of [weird tokens](https://github.com/d-xo/weird-erc20) you want to integrate?
The PinlinkShop contract is expected to work with:
- PIN ERC20 token (already deployed in mainnet at https://etherscan.io/address/0x2e44f3f609ff5aA4819B323FD74690f07C3607c4). This is the only token that can be used as a payment method for the purchase of assets in the PinlinkShop. 
- Official USDC ERC20 token (https://etherscan.io/token/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48). This is the only token used for distribution of rewards to holders of assets within the PinlinkShop contract. 

No other token is expected to interact with the system.
___

### Q: Are there any limitations on values set by admins (or other roles) in the codebase, including restrictions on array lengths?
- The `feeReceiver` is a trusted address, and is a parameter that can be modified by DEFAULT_ADMIN_ROLE.
- The `purchaseFeePerc` is the fee taken on every purchase in PIN tokens. This value can be updated by DEFAULT_ADMIN_ROLE, but cannot exceed 10%.
- The `owner` of the `CentralizedOracle` is trusted. That's the one allowed to update the price of the token PIN that will be used in the PinlinkShop to covert between PIN and USD pricing. To begin with, the `CentralizedOracle` is centralized and operated by Pinlink. With time, this will be replaced with a TWAP oracle or even a Chainlink Price feed if possible.
- Only accounts with the OPERATOR role can deposit rewards
- Only accounts with the OPERATOR role can collect rewards that have been unassigned due to users withdrawing their assets from the PinlinkShop. These unassigned rewards are allocated REWARDS_PROXY_ACCOUNT until claimed by the OPERATOR role

___

### Q: Are there any limitations on values set by admins (or other roles) in protocols you integrate with, including restrictions on array lengths?
No.
___

### Q: Is the codebase expected to comply with any specific EIPs?
The `FractionalAsset` is expected to comply with ERC1155, of fixed (immutable) totalSupply for each of the tokenIds. Once minted, the number of fractions is immutable. 
___

### Q: Are there any off-chain mechanisms involved in the protocol (e.g., keeper bots, arbitrage bots, etc.)? We assume these mechanisms will not misbehave, delay, or go offline unless otherwise specified.
The price given by the `CentralizedOracle` will be set by a bot which checks the price from different sources (coingecko, Uniswap pool moving average, etc) and after some sanity checks it calls `updateTokenPrice()`. 

- The bot will only check every X minutes if price needs to be updated (X to be defined)
- The bot only updates the price if it differs from the current oracle price in more than Y% (to be defined)
___

### Q: What properties/invariants do you want to hold even if breaking them has a low/unknown impact?
- Rewards solvency: 
  - the addition of all `getPendingRewards()` from all accounts and assets should be less or equal to the contract balance of USDC. 
  - When the current drippingPeriod is finished, it should be equal. A small rounding error is accepted (less than 0.01 % for instance). 

- Asset balances: for a given user and an asset, `stakedBalance == listedBalance + unlistedBalance`

- Each fraction of an asset is always entitled to the same share of rewards, proportional to his stakedBalance in the PinlinkShop contract vs the totalSupply of that asset. This should still hold even when some users withdraw their assets outside PinlinkShop. In this case, rewards are not redistributed between the remaining stakers, but allocated to the PROXY_REWARDS_ACCOUNT, to be later claimed by an admin. 

- listed assets continue generating rewards for the seller until sold. 

- The total stakedBalance of an asset should not change once it is enabled, and should match the assetSupply.


___

### Q: Please discuss any design choices you made.
The PinlinkShop could have been split into multiple contracts (marketplace, staking, a manager...) but we decided to go for a simple architecture consists of a single contract in charge of the two functionalities:
- buy/sell marketplace of fractionalized assets
- staking

This allowed an easy way of keep streaming rewards for holders of fractional assets while they are being listed for sale. Discontinuing rewards for sellers while being listed was not desired. 

Users are allowed to withdraw the assets outside the PinlinkShop, to trade them in a different marketplace, but this doesn't entitle them to earn rewards anymore. 
___

### Q: Please provide links to previous audits (if any).
There was an audit done to the first version of the protocol. However, the project has pivoted, so it is far from useful for this competition. In any case:

https://github.com/JacoboLansac/audits/blob/main/solo/pinlink-phase1-audit.md
___

### Q: Please list any relevant protocol resources.
None.
___

### Q: Additional audit information.
- Fractional assets ownership
- Rewards accountability and solvency
- DoS


# Audit scope

[marketplace-contracts @ f4d5261b82e21ce8d42dcb737489ac0e2ead45d6](https://github.com/PinLinkNetwork/marketplace-contracts/tree/f4d5261b82e21ce8d42dcb737489ac0e2ead45d6)
- [marketplace-contracts/src/fractional/FractionalAssets.sol](marketplace-contracts/src/fractional/FractionalAssets.sol)
- [marketplace-contracts/src/fractional/IFractionalAssets.sol](marketplace-contracts/src/fractional/IFractionalAssets.sol)
- [marketplace-contracts/src/marketplaces/pinlinkShop.sol](marketplace-contracts/src/marketplaces/pinlinkShop.sol)
- [marketplace-contracts/src/marketplaces/streams.sol](marketplace-contracts/src/marketplaces/streams.sol)
- [marketplace-contracts/src/oracles/CentralizedOracle.sol](marketplace-contracts/src/oracles/CentralizedOracle.sol)
- [marketplace-contracts/src/oracles/IPinlinkOracle.sol](marketplace-contracts/src/oracles/IPinlinkOracle.sol)


