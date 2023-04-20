## Deploy Velodrome v2

Velodrome v2 deployment is a multi-step process.  Unlike testing, we cannot impersonate governance to submit transactions and must wait on the necessary protocol actions to complete setup.  This README goes through the necessary instructions to deploy the Velodrome v2 upgrade.

### Environment setup
1. Copy-pasta `.env.sample` into a new `.env` and set the environment variables. `PRIVATE_KEY_DEPLOY` is the private key to deploy all scripts.
2. Copy-pasta `script/constants/TEMPLATE.json` into a new file `script/constants/{CONSTANTS_FILENAME}`. For example, "Optimism.json" in the .env would be a file of `script/constants/Optimism.json`.  Set the variables in the new file.

3. Run tests to ensure deployment state is configured correctly:
```ml
forge init
forge build
forge test
```

*Note that this will create a `script/constants/output/{OUTPUT_FILENAME}` file with the contract addresses created in testing.  If you are using the same constants for multiple deployments (for example, deploying in a local fork and then in prod), you can rename `OUTPUT_FILENAME` to store the new contract addresses while using the same constants.

4. Ensure all v2 deployments are set properly. In project directory terminal:
```
source .env
```

### Deployment
- Note that if deploying to a chain other than Optimism/Optimism Goerli, if you have a different .env variable name used for `RPC_URL`, `SCAN_API_KEY` and `ETHERSCAN_VERIFIER_URL`, you will need to use the corresponding chain name by also updating `foundry.toml`.  For this example we're deploying onto Optimism.

1. Deploy SinkDrain
```
forge script script/DeploySinkDrain.s.sol:DeploySinkDrain --broadcast --rpc-url optimism --verify -vvvv
```

2. Create a custom gauge on v1 using the address of the `SinkDrain` deployed.  The contract address of `SinkDrain` can be located within `script/constants/output/{OUTPUT_FILENAME}`.  This is done through calling the v1 `voter.createGauge()` with the function argument being the `SinkDrain` address.  This gauge needs to be created by the v1 `escrow.team()` address.

3. Deploy Velodrome v2 Core
```
forge script script/DeployVelodromeV2.s.sol:DeployVelodromeV2 --broadcast --rpc-url optimism --verify -vvvv
```

4. Deploy v1 gauges.  These gauges are built on Velodrome v2 using existing v1 pairs.
```
forge script script/DeployGaugesV1.s.sol:DeployGaugesV1 --broadcast --rpc-url optimism --verify -vvvv
```

5. Deploy v2 gauges and v2 pairs.  These gauges are built on Velodrome v2 using newly created v2 pairs.
```
forge script script/DeployGaugesAndPairsV2.s.sol:DeployGaugesAndPairsV2 --broadcast --rpc-url optimism --verify -vvvv
```

6. Deploy governor contracts
```
forge script script/DeployGovernors.s.sol:DeployGovernors --broadcast --rpc-url optimism --verify -vvvv
```
7.  Update the governor addresses on v2.  This needs to be done by the v2 `escrow.team()` address.  Within v2 `voter`:
 - call `setEpochGovernor()` using the `EpochGovernor` address located in `script/constants/output/{OUTPUT_FILENAME}`
 - call `setGovernor()` using the `Governor` address located in the same file.

8. Accept governor vetoer status.  This also needs to be done by the v2 `escrow.team()` address.  Within the deployed `Governor` contract call `acceptVetoer()`.