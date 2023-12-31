import {
  ChainlinkAdapter__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../typechain';
import { ethers } from 'hardhat';
import {
  ContractKey,
  ContractType,
  initialize,
  proposeOrSendTransaction,
  updateDeploymentMetadata,
} from '../utils';

async function main() {
  const [deployer, proposer] = await ethers.getSigners();
  const { deployment, proposeToMultiSig } = await initialize(deployer);

  //////////////////////////

  let weth: string;
  let wbtc: string;

  weth = deployment.tokens.WETH;
  wbtc = deployment.tokens.WBTC;

  //////////////////////////

  const args = [weth, wbtc];
  const implementation = await new ChainlinkAdapter__factory(deployer).deploy(
    args[0],
    args[1],
  );
  await updateDeploymentMetadata(
    deployer,
    ContractKey.ChainlinkAdapterImplementation,
    ContractType.Implementation,
    implementation,
    args,
    { logTxUrl: true, verification: { enableVerification: true } },
  );

  const proxy = ProxyUpgradeableOwnable__factory.connect(
    deployment.core.ChainlinkAdapterProxy.address,
    deployer,
  );

  const transaction = await proxy.populateTransaction.setImplementation(
    implementation.address,
  );

  await proposeOrSendTransaction(
    proposeToMultiSig,
    deployment.addresses.treasury,
    proposeToMultiSig ? proposer : deployer,
    [transaction],
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
