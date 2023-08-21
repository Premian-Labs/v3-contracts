import {
  ChainlinkAdapter__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../typechain';
import { PoolUtil } from '../../utils/PoolUtil';
import { arbitrumFeeds, arbitrumGoerliFeeds } from '../../utils/addresses';
import { parseEther } from 'ethers/lib/utils';
import { ethers } from 'hardhat';
import {
  ChainID,
  ContractKey,
  ContractType,
} from '../../utils/deployment/types';
import {
  initialize,
  updateDeploymentMetadata,
} from '../../utils/deployment/deployment';

async function main() {
  const [deployer] = await ethers.getSigners();
  const { network, deployment } = await initialize(deployer);

  //////////////////////////

  let weth: string;
  let wbtc: string;
  let vxPremia: string | undefined;
  let feeReceiver: string;
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
    true,
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
    true,
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

  const discountPerPool = parseEther('0.1'); // 10%
  const log = true;

  await PoolUtil.deploy(
    deployer,
    weth,
    chainlinkAdapter,
    deployment.feeConverter.main.address,
    deployment.addresses.insuranceFund, // Not using `feeConverter` here, as this is used to receive ETH, which is not supported by `feeConverter`
    discountPerPool,
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
