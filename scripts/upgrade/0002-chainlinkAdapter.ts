import {
  ChainlinkAdapter__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../typechain';
import arbitrumDeployment from '../../utils/deployment/arbitrum.json';
import arbitrumGoerliDeployment from '../../utils/deployment/arbitrumGoerli.json';
import {
  ChainID,
  ContractKey,
  ContractType,
  DeploymentInfos,
} from '../../utils/deployment/types';
import { ethers } from 'hardhat';
import { updateDeploymentInfos } from '../../utils/deployment/deployment';
import { proposeOrSendTransaction } from '../utils/safe';

async function main() {
  const [deployer, proposer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  //////////////////////////

  let deployment: DeploymentInfos;
  let weth: string;
  let wbtc: string;
  let proposeToMultiSig: boolean;

  if (chainId === ChainID.Arbitrum) {
    deployment = arbitrumDeployment;
    proposeToMultiSig = true;
  } else if (chainId === ChainID.ArbitrumGoerli) {
    deployment = arbitrumGoerliDeployment;
    proposeToMultiSig = false;
  } else {
    throw new Error('ChainId not implemented');
  }

  weth = deployment.tokens.WETH;
  wbtc = deployment.tokens.WBTC;

  //////////////////////////

  const args = [weth, wbtc];
  const implementation = await new ChainlinkAdapter__factory(deployer).deploy(
    args[0],
    args[1],
  );
  await updateDeploymentInfos(
    deployer,
    ContractKey.ChainlinkAdapterImplementation,
    ContractType.Implementation,
    implementation,
    args,
    true,
  );

  const proxy = ProxyUpgradeableOwnable__factory.connect(
    deployment.ChainlinkAdapterProxy.address,
    deployer,
  );

  const transaction = await proxy.populateTransaction.setImplementation(
    implementation.address,
  );

  await proposeOrSendTransaction(
    proposeToMultiSig,
    deployment.treasury,
    proposer,
    [transaction],
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
