import {
  ChainlinkAdapter__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../typechain';
import { PoolUtil } from '../../utils/PoolUtil';
import { arbitrumFeeds, arbitrumGoerliFeeds } from '../../utils/addresses';
import arbitrumDeployment from '../../utils/deployment/arbitrum.json';
import arbitrumGoerliDeployment from '../../utils/deployment/arbitrumGoerli.json';
import { parseEther } from 'ethers/lib/utils';
import { ethers } from 'hardhat';
import {
  ChainID,
  ContractKey,
  ContractType,
  DeploymentInfos,
} from '../../utils/deployment/types';
import { updateDeploymentInfos } from '../../utils/deployment/deployment';

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  //////////////////////////

  let weth: string;
  let wbtc: string;
  let vxPremia: string | undefined;
  let feeReceiver: string;
  let chainlinkAdapter: string;

  let deployment: DeploymentInfos;

  if (chainId === ChainID.Arbitrum) {
    deployment = arbitrumDeployment;
  } else if (chainId == ChainID.ArbitrumGoerli) {
    deployment = arbitrumGoerliDeployment;
  } else {
    throw new Error('ChainId not implemented');
  }

  weth = deployment.tokens.WETH;
  wbtc = deployment.tokens.WBTC;
  vxPremia = deployment.VxPremiaProxy.address;

  //////////////////////////
  // Deploy ChainlinkAdapter
  const chainlinkAdapterImplArgs = [weth, wbtc];
  const chainlinkAdapterImpl = await new ChainlinkAdapter__factory(
    deployer,
  ).deploy(chainlinkAdapterImplArgs[0], chainlinkAdapterImplArgs[1]);
  await updateDeploymentInfos(
    deployer,
    ContractKey.ChainlinkAdapterImplementation,
    ContractType.Implementation,
    chainlinkAdapterImpl,
    chainlinkAdapterImplArgs,
    true,
  );

  const chainlinkAdapterProxyArgs = [chainlinkAdapterImpl.address];
  const chainlinkAdapterProxy = await new ProxyUpgradeableOwnable__factory(
    deployer,
  ).deploy(chainlinkAdapterProxyArgs[0]);
  await updateDeploymentInfos(
    deployer,
    ContractKey.ChainlinkAdapterProxy,
    ContractType.Proxy,
    chainlinkAdapterProxy,
    chainlinkAdapterProxyArgs,
    true,
  );

  chainlinkAdapter = chainlinkAdapterProxy.address;

  if (chainId === ChainID.Arbitrum) {
    await ChainlinkAdapter__factory.connect(
      chainlinkAdapter,
      deployer,
    ).batchRegisterFeedMappings(arbitrumFeeds);
  } else if (chainId === ChainID.ArbitrumGoerli) {
    await ChainlinkAdapter__factory.connect(
      chainlinkAdapter,
      deployer,
    ).batchRegisterFeedMappings(arbitrumGoerliFeeds);
  } else {
    throw new Error('ChainId not implemented');
  }

  //////////////////////////

  const discountPerPool = parseEther('0.1'); // 10%
  const log = true;

  await PoolUtil.deploy(
    deployer,
    weth,
    chainlinkAdapter,
    deployment.feeConverter.main.address,
    deployment.insuranceFund, // Not using `feeConverter` here, as this is used to receive ETH, which is not supported by `feeConverter`
    discountPerPool,
    log,
    vxPremia,
    deployment.tokens.PREMIA,
    deployment.tokens.USDC,
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
