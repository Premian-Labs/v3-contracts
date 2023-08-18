import fs from 'fs';
import _ from 'lodash';
import * as prettier from 'prettier';
import { render } from 'mustache';
import {
  BlockExplorerUrl,
  ChainName,
  ContractKey,
  DeploymentInfos,
  DeploymentJsonPath,
} from './types';
import { Network } from '@ethersproject/networks';
import { getContractFilePath } from './deployment';

const tableTemplateNoHeader = `# {{chain}} : {{name}} Deployments
|Contract      |Description|Address|    |
|--------------|-----------|-------|----|
{{#sections}}
{{>partial}}
{{/sections}}`;

const summaryPartial = `{{#contracts}}|\`{{{name}}}\`|{{description}}|{{{displayAddress}}}|{{{displayEtherscanUrl}}}|\n{{/contracts}}`;

const tableTemplate = `# {{chain}} : {{name}} Deployments
|Contract      |Description|Address|    |    |
|--------------|-----------|-------|----|----|
{{#sections}}
{{displayHeader}}
{{>partial}}
{{/sections}}`;

const detailedSummaryPartial = `{{#contracts}}|\`{{{name}}}\`|{{description}}|{{{displayAddress}}}|{{{displayEtherscanUrl}}}|{{{displayFilePathUrl}}}|\n{{/contracts}}`;

function displayHeader() {
  if (this.name.length > 0 || this.name !== '') return `|**${this.name}**|||||`;
  else return '||||||';
}

function displayAddress() {
  if (this.address.length > 0 || this.address !== '')
    return `\`${this.address}\``;
  else return '';
}

function displayEtherscanUrl() {
  if (this.address.length > 0 || this.address !== '')
    return `[🔗](${this.etherscanUrl}/address/${this.address})`;
  else return '';
}

function displayFilePathUrl() {
  if (this.commitHash.length > 0 || this.commitHash !== '') {
    const contractFilePath = getContractFilePath(this.name);
    return `[📁](https://github.com/Premian-Labs/premia-v3-contracts-private/blob/${this.commitHash}/${contractFilePath})`;
  } else return '';
}

export async function buildTable(network: Network) {
  const chain = ChainName[network.chainId];

  let tableData: TableData = {
    categories: {
      vaults: {
        name: 'Vault',
        chain,
        sections: [],
        displayHeader,
      },
      optionPS: {
        name: 'Physically Settled Option',
        chain,
        sections: [],
        displayHeader,
      },
      optionReward: {
        name: 'Option Reward',
        chain,
        sections: [],
        displayHeader,
      },
      core: {
        name: 'Core Contract',
        chain,
        sections: [],
        displayHeader,
      },
    },
  };

  const etherscanUrl = BlockExplorerUrl[network.chainId];

  const deployData = JSON.parse(
    fs.readFileSync(DeploymentJsonPath[network.chainId]).toString(),
  ) as DeploymentInfos;

  for (const key in deployData) {
    if (key === 'vaults' || key === 'optionReward' || key === 'optionPS') {
      const category = tableData.categories[key];

      category.sections.push({
        name: '',
        contracts: [],
      });

      for (let contract in deployData[key]) {
        let contractData = deployData[key][contract];

        let contractInfo: Contract = {
          name: contract,
          description: '',
          address: contractData.address,
          etherscanUrl,
          displayAddress,
          displayEtherscanUrl,
        };

        category.sections[0].contracts.push(contractInfo);
      }
    } else if (key in ContractKey) {
      const category = tableData.categories.core;
      const contractMetadata = CoreContractMetaData[key];

      let sectionIndex = _.findIndex(category.sections, [
        'name',
        contractMetadata.section,
      ]);

      if (sectionIndex === -1) {
        category.sections.push({
          name: contractMetadata.section,
          contracts: [],
        });

        sectionIndex = category.sections.length - 1;
      }

      let contractData = deployData[key as ContractKey];

      let contractInfo: Contract = {
        name: contractMetadata.name,
        description: '',
        address: contractData.address,
        commitHash: contractData.commitHash,
        etherscanUrl,
        displayAddress,
        displayEtherscanUrl,
        displayFilePathUrl,
      };

      category.sections[sectionIndex].contracts.push(contractInfo);
    }
  }

  for (const key in tableData.categories) {
    const category = tableData.categories[key];

    let template = tableTemplate;
    let partial = detailedSummaryPartial;

    if (key === 'vaults' || key === 'optionReward' || key === 'optionPS') {
      template = tableTemplateNoHeader;
      partial = summaryPartial;
    }

    // Generate md file from template
    let table = render(template, category, { partial });

    // Prettify table markdown
    table = prettier.format(table, { parser: 'markdown' });

    console.log(table);

    // Overwrite table.md
    // fs.writeFileSync('utils/deployment/table.md', table);
  }
}

interface TableData {
  categories: {
    [key: string]: {
      name: string;
      chain: string;
      sections: Section[];
      displayHeader: () => string;
    };
  };
}

type Section = {
  name: string;
  contracts: Contract[];
};

type Contract = {
  name: string;
  description: string;
  address: string;
  commitHash?: string;
  etherscanUrl: string;
  displayAddress: () => string;
  displayEtherscanUrl: () => string;
  displayFilePathUrl?: () => string;
};

const CoreContractMetaData: { [name: string]: MetaData } = {
  ChainlinkAdapterImplementation: {
    name: 'ChainlinkAdapter',
    section: 'Adapter',
    description: 'Chainlink Adapter Implementation',
  },
  ChainlinkAdapterProxy: {
    name: 'ProxyUpgradeableOwnable',
    section: 'Adapter',
    description: 'Chainlink Adapter Proxy',
  },
  PremiaDiamond: {
    name: 'Premia',
    section: 'Premia Core',
    description: '',
  },
  PoolFactoryImplementation: {
    name: 'PoolFactory',
    section: 'Premia Core',
    description: '',
  },
  PoolFactoryProxy: {
    name: 'PoolFactoryProxy',
    section: 'Premia Core',
    description: '',
  },
  PoolFactoryDeployer: {
    name: 'PoolFactoryDeployer',
    section: 'Premia Core',
    description: '',
  },
  UserSettingsImplementation: {
    name: 'UserSettings',
    section: 'Pool Architecture',
    description: '',
  },
  UserSettingsProxy: {
    name: 'ProxyUpgradeableOwnable',
    section: 'Pool Architecture',
    description: '',
  },
  ExchangeHelper: {
    name: 'ExchangeHelper',
    section: 'Pool Architecture',
    description: '',
  },
  ReferralImplementation: {
    name: 'Referral',
    section: 'Pool Architecture',
    description: '',
  },
  ReferralProxy: {
    name: 'ReferralProxy',
    section: 'Pool Architecture',
    description: '',
  },
  VxPremiaImplementation: {
    name: 'VxPremia',
    section: 'Premia Core',
    description: '',
  },
  VxPremiaProxy: {
    name: 'VxPremiaProxy',
    section: 'Premia Core',
    description: '',
  },
  ERC20Router: {
    name: 'ERC20Router',
    section: 'Premia Core',
    description: '',
  },
  PoolBase: {
    name: 'PoolBase',
    section: 'Pool Architecture',
    description: '',
  },
  PoolCore: {
    name: 'PoolCore',
    section: 'Pool Architecture',
    description: '',
  },
  PoolDepositWithdraw: {
    name: 'PoolDepositWithdraw',
    section: 'Pool Architecture',
    description: '',
  },
  PoolTrade: {
    name: 'PoolTrade',
    section: 'Pool Architecture',
    description: '',
  },
  OrderbookStream: {
    name: 'OrderbookStream',
    section: 'Miscellaneous',
    description: '',
  },
  VaultRegistryImplementation: {
    name: 'VaultRegistry',
    section: 'Periphery',
    description: '',
  },
  VaultRegistryProxy: {
    name: 'ProxyUpgradeableOwnable',
    section: 'Periphery',
    description: '',
  },
  VolatilityOracleImplementation: {
    name: 'VolatilityOracle',
    section: 'Periphery',
    description: '',
  },
  VolatilityOracleProxy: {
    name: 'ProxyUpgradeableOwnable',
    section: 'Periphery',
    description: '',
  },
  OptionMathExternal: {
    name: 'OptionMathExternal',
    section: 'Periphery',
    description: '',
  },
  UnderwriterVaultImplementation: {
    name: 'UnderwriterVault',
    section: 'Periphery',
    description: '',
  },
  VaultMiningImplementation: {
    name: 'VaultMining',
    section: 'Periphery',
    description: '',
  },
  VaultMiningProxy: {
    name: 'VaultMiningProxy',
    section: 'Periphery',
    description: '',
  },
  OptionPSFactoryImplementation: {
    name: 'OptionPSFactory',
    section: 'Miscellaneous',
    description: '',
  },
  OptionPSFactoryProxy: {
    name: 'ProxyUpgradeableOwnable',
    section: 'Miscellaneous',
    description: '',
  },
  OptionPSImplementation: {
    name: 'OptionPS',
    section: 'Miscellaneous',
    description: '',
  },
  OptionRewardFactoryImplementation: {
    name: 'OptionRewardFactory',
    section: 'Periphery',
    description: '',
  },
  OptionRewardFactoryProxy: {
    name: 'ProxyUpgradeableOwnable',
    section: 'Periphery',
    description: '',
  },
  OptionRewardImplementation: {
    name: 'OptionReward',
    section: 'Periphery',
    description: '',
  },
  FeeConverterImplementation: {
    name: 'FeeConverter',
    section: 'Miscellaneous',
    description: '',
  },
};

interface MetaData {
  name: string;
  section: string;
  description: string;
}
