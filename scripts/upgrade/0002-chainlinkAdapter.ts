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

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  //////////////////////////

  let deployment: DeploymentInfos;
  let weth: string;
  let wbtc: string;
  let setImplementation: boolean;

  if (chainId === ChainID.Arbitrum) {
    // Arbitrum
    deployment = arbitrumDeployment;
    setImplementation = false;
  } else if (chainId === ChainID.ArbitrumGoerli) {
    deployment = arbitrumGoerliDeployment;
    setImplementation = true;
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

  if (setImplementation) {
    const proxy = ProxyUpgradeableOwnable__factory.connect(
      deployment.ChainlinkAdapterProxy.address,
      deployer,
    );
    await proxy.setImplementation(implementation.address);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
