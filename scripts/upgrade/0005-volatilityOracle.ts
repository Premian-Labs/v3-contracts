import {
  ProxyUpgradeableOwnable__factory,
  VolatilityOracle__factory,
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

  //////////////////////////

  const implementation = await new VolatilityOracle__factory(deployer).deploy();
  await updateDeploymentInfos(
    deployer,
    ContractKey.VolatilityOracleImplementation,
    ContractType.Implementation,
    implementation,
    [],
    true,
  );

  const proxy = ProxyUpgradeableOwnable__factory.connect(
    deployment.VolatilityOracleProxy.address,
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
    false,
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
