import {
  VaultMining__factory,
  VaultMiningProxy__factory,
  VxPremiaProxy,
} from '../../typechain';
import { ethers } from 'hardhat';
import {
  ChainID,
  ContractKey,
  ContractType,
  DeploymentInfos,
} from '../../utils/deployment/types';
import arbitrumDeployment from '../../utils/deployment/arbitrum.json';
import arbitrumGoerliDeployment from '../../utils/deployment/arbitrumGoerli.json';
import { updateDeploymentInfos } from '../../utils/deployment/deployment';

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  //////////////////////////

  let proxy: VxPremiaProxy;
  let deployment: DeploymentInfos;
  let addressesPath: string;
  let setImplementation: boolean;

  if (chainId === ChainID.Arbitrum) {
    deployment = arbitrumDeployment;
    addressesPath = 'utils/deployment/arbitrum.json';
    setImplementation = false;
  } else if (chainId === ChainID.ArbitrumGoerli) {
    deployment = arbitrumGoerliDeployment;
    addressesPath = 'utils/deployment/arbitrumGoerli.json';
    setImplementation = true;
  } else {
    throw new Error('ChainId not implemented');
  }

  // ToDo : Deploy OptionReward contract

  //////////////////////////

  const vaultMiningImplementationArgs = [
    deployment.VaultRegistryProxy.address,
    deployment.tokens.PREMIA,
    deployment.VxPremiaProxy.address,
    deployment.optionReward['PREMIA/USDC'],
  ];

  const vaultMiningImplementation = await new VaultMining__factory(
    deployer,
  ).deploy(
    vaultMiningImplementationArgs[0],
    vaultMiningImplementationArgs[1],
    vaultMiningImplementationArgs[2],
    vaultMiningImplementationArgs[3],
  );

  await updateDeploymentInfos(
    deployer,
    ContractKey.VaultMiningImplementation,
    ContractType.Implementation,
    vaultMiningImplementation,
    vaultMiningImplementationArgs,
    true,
  );

  //////////////////////////

  const rewardsPerYear = 0; // ToDo : Set

  const vaultMiningProxyArgs = [
    vaultMiningImplementation.address,
    rewardsPerYear.toString(),
  ];
  const vaultMiningProxy = await new VaultMiningProxy__factory(deployer).deploy(
    vaultMiningProxyArgs[0],
    vaultMiningProxyArgs[1],
  );
  await updateDeploymentInfos(
    deployer,
    ContractKey.VaultMiningProxy,
    ContractType.Proxy,
    vaultMiningProxy,
    vaultMiningProxyArgs,
    true,
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
