# Deployment plan

- blockchain: ethereum mainnet

## Oracle

```bash
forge create src/oracles/CentralizedOracle.sol:CentralizedOracle \
--rpc-url $SEPOLIA_RPC_URL \
--private-key $PINDEV_PKEY \
--broadcast \
--verify \
--constructor-args 0xb7c06D906C7CB7193Eb4D8ADC25983aEaf99729f 950000000000000000
```

## Fractional Assets

- Deploy using forge create. No contractURI, because our metadata requires also the contract address in the contract URI, and `address(this)` can yield unexpected results in the constructor.

```bash
forge create src/fractional/FractionalAssets.sol:FractionalAssets \
--rpc-url $SEPOLIA_RPC_URL \
--private-key $PINDEV_PKEY \
--broadcast \
--verify
```

- Update the address and the contractURI in `script/fracitonal/setupFractional.s.sol`

- Run the script to update URI and mint assets:

```bash
forge script script/fracitonal/setupFractional.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $PINDEV_PKEY --broadcast
```

### Access control

- Grant `DEFAULT_ADMIN_ROLE` to Pinlink Multisig
- Grant `MINTER_ADMIN_ROLE` to Pinlink Multisig
- Revoke `DEFAULT_ADMIN_ROLE` to from deployer address


## Pinlink Shop

Update the constructor args below with
- PIN ERC20 token
- Pin oracle (Centralized Oracle for now)
- Reward token (USDC)

```bash
forge create src/marketplaces/pinlinkShop.sol:PinlinkShop \
--private-key $PINDEV_PKEY \
--rpc-url $SEPOLIA_RPC_URL \
--verify \
--broadcast \
--constructor-args 0xb7c06D906C7CB7193Eb4D8ADC25983aEaf99729f 0xc13827D7B2Cd3309952352D0C030e96bc7b9fcF5 0x31548a5e3504bffd5cd9a350d1dfcc66c1ab7ddb
```

- Update addresses in script: `script/pinlinkShpo/setupPinlinkShop.s.sol`
- run the script 

```bash
forge script script/pinlinkshop/setupPinlinkShop.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $PINDEV_PKEY --broadcast
```