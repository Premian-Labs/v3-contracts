import {
  ChainlinkAdapter__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../typechain';
import { PoolUtil } from '../../utils/PoolUtil';
import { arbitrumGoerliFeeds } from '../../utils/addresses';
import arbitrumAddresses from '../../utils/deployment/arbitrum.json';
import arbitrumGoerliAddresses from '../../utils/deployment/arbitrumGoerli.json';
import { parseEther } from 'ethers/lib/utils';
import { ethers } from 'hardhat';
import { ChainID, ContractAddresses } from '../../utils/deployment/types';

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  //////////////////////////

  let weth: string;
  let wbtc: string;
  let vxPremia: string | undefined;
  let feeReceiver: string;
  let chainlinkAdapter: string;

  let addresses: ContractAddresses;

  if (chainId === ChainID.Arbitrum) {
    addresses = arbitrumAddresses;
  } else if (chainId == ChainID.ArbitrumGoerli) {
    addresses = arbitrumGoerliAddresses;
  } else {
    throw new Error('ChainId not implemented');
  }

  weth = addresses.tokens.WETH;
  wbtc = addresses.tokens.WBTC;
  feeReceiver = addresses.feeReceiver;
  vxPremia = addresses.VxPremiaProxy;

  //////////////////////////
  // Deploy ChainlinkAdapter
  const chainlinkAdapterImpl = await new ChainlinkAdapter__factory(
    deployer,
  ).deploy(weth, wbtc);
  await chainlinkAdapterImpl.deployed();
  console.log(`ChainlinkAdapter impl : ${chainlinkAdapterImpl.address}`);

  const chainlinkAdapterProxy = await new ProxyUpgradeableOwnable__factory(
    deployer,
  ).deploy(chainlinkAdapterImpl.address);
  await chainlinkAdapterProxy.deployed();

  console.log(`ChainlinkAdapter proxy : ${chainlinkAdapterProxy.address}`);

  chainlinkAdapter = chainlinkAdapterProxy.address;

  if (chainId == ChainID.ArbitrumGoerli) {
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
  const isDevMode = false;

  await PoolUtil.deploy(
    deployer,
    weth,
    chainlinkAdapter,
    feeReceiver,
    discountPerPool,
    log,
    isDevMode,
    vxPremia,
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
