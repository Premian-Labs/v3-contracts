import {
  ChainlinkAdapter__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../typechain';
import { arbitrumFeeds, arbitrumGoerliFeeds } from '../utils';
import { ethers } from 'hardhat';
import {
  ChainID,
  ContractKey,
  ContractType,
  initialize,
  updateDeploymentMetadata,
  PoolUtil,
} from '../utils';

async function main() {
  const [deployer] = await ethers.getSigners();
  const { network, deployment } = await initialize(deployer);

  //////////////////////////

  let weth: string;
  let wbtc: string;
  let vxPremia: string | undefined;
  let chainlinkAdapter: string;

  weth = deployment.tokens.WETH;
  wbtc = deployment.tokens.WBTC;
  vxPremia = deployment.core.VxPremiaProxy.address;

  //////////////////////////
  // Deploy ChainlinkAdapter
  const chainlinkAdapterImplArgs = [weth, wbtc];
  const chainlinkAdapterImpl = await new ChainlinkAdapter__factory(
    deployer,
  ).deploy(chainlinkAdapterImplArgs[0], chainlinkAdapterImplArgs[1]);
  await updateDeploymentMetadata(
    deployer,
    ContractKey.ChainlinkAdapterImplementation,
    ContractType.Implementation,
    chainlinkAdapterImpl,
    chainlinkAdapterImplArgs,
    { logTxUrl: true },
  );

  const chainlinkAdapterProxyArgs = [chainlinkAdapterImpl.address];
  const chainlinkAdapterProxy = await new ProxyUpgradeableOwnable__factory(
    deployer,
  ).deploy(chainlinkAdapterProxyArgs[0]);
  await updateDeploymentMetadata(
    deployer,
    ContractKey.ChainlinkAdapterProxy,
    ContractType.Proxy,
    chainlinkAdapterProxy,
    chainlinkAdapterProxyArgs,
    { logTxUrl: true },
  );

  chainlinkAdapter = chainlinkAdapterProxy.address;

  if (network.chainId === ChainID.Arbitrum) {
    await ChainlinkAdapter__factory.connect(
      chainlinkAdapter,
      deployer,
    ).batchRegisterFeedMappings(arbitrumFeeds);
  } else if (network.chainId === ChainID.ArbitrumGoerli) {
    await ChainlinkAdapter__factory.connect(
      chainlinkAdapter,
      deployer,
    ).batchRegisterFeedMappings(arbitrumGoerliFeeds);
  } else {
    throw new Error('ChainId not implemented');
  }

  //////////////////////////

  const log = true;

  await PoolUtil.deploy(
    deployer,
    weth,
    deployment.feeConverter.main.address,
    log,
    vxPremia,
    deployment.tokens.PREMIA,
    deployment.tokens.USDC,
    deployment.core.ExchangeHelper.address,
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
