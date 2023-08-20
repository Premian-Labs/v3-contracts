import fs from 'fs';
import _ from 'lodash';
import * as prettier from 'prettier';
import { render } from 'mustache';
import {
  BlockExplorerUrl,
  ChainName,
  ContractKey,
  ContractType,
  DeploymentMetadata,
  DeploymentPath,
} from '../deployment/types';
import { Network } from '@ethersproject/networks';
import {
  getContractFilePath,
  getContractFilePaths,
} from '../deployment/deployment';
import {
  tableTemplateNoHeader,
  tableTemplate,
  summaryPartial,
  detailedSummaryPartial,
} from './template';
import {
  TableData,
  Contract,
  NameOverride,
  DescriptionOverride,
} from './types';

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
  if (
    (this.commitHash.length > 0 || this.commitHash !== '') &&
    (this.filePath.length > 0 || this.filePath !== '')
  ) {
    return `[📁](https://github.com/Premian-Labs/premia-v3-contracts-private/blob/${this.commitHash}/${this.filePath})`;
  } else return '';
}

let tableView: TableData = {
  categories: {
    vaults: {
      name: 'Vault',
      chain: '',
      sections: [],
      displayHeader,
    },
    optionPS: {
      name: 'Physically Settled Option',
      chain: '',
      sections: [],
      displayHeader,
    },
    optionReward: {
      name: 'Option Reward',
      chain: '',
      sections: [],
      displayHeader,
    },
    core: {
      name: 'Core Contract',
      chain: '',
      sections: [],
      displayHeader,
    },
  },
};

export async function generateTables(network: Network) {
  const chain = ChainName[network.chainId];
  const etherscanUrl = BlockExplorerUrl[network.chainId];
  const deploymentPath = DeploymentPath[network.chainId];

  const deploymentMetadata = JSON.parse(
    fs.readFileSync(`${deploymentPath}/metadata.json`).toString(),
  ) as DeploymentMetadata;

  updateTableView(deploymentMetadata, chain, etherscanUrl);
  writeTables(deploymentPath, chain);
}

function updateTableView(
  deploymentMetadata: DeploymentMetadata,
  chain: string,
  etherscanUrl: string,
) {
  const contractFilePaths = getContractFilePaths();

  for (const key in deploymentMetadata) {
    // Update Vaults, OptionReward, and OptionPS views
    if (key === 'vaults' || key === 'optionReward' || key === 'optionPS') {
      if (chain === 'Arbitrum Nova') continue;
      const category = tableView.categories[key];
      category.chain = chain;

      category.sections.push({
        name: '',
        contracts: [],
      });

      for (let contract in deploymentMetadata[key]) {
        const contractData = deploymentMetadata[key][contract];

        const contractInfo: Contract = {
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
      // Update Core view
      const category = tableView.categories.core;
      category.chain = chain;

      const contractData = deploymentMetadata[key as ContractKey];
      const contractName = inferContractName(key, contractData.contractType);

      const filePath = getContractFilePath(contractName, contractFilePaths);
      let section = filePath.split('/')[1];
      // Capitalize first letter of section
      section = section.charAt(0).toUpperCase() + section.slice(1);

      let sectionIndex = _.findIndex(category.sections, ['name', section]);

      if (sectionIndex === -1) {
        category.sections.push({
          name: section,
          contracts: [],
        });

        sectionIndex = category.sections.length - 1;
      }

      const contractInfo: Contract = {
        name: contractName,
        description: inferContractDescription(key, contractData.contractType),
        address: contractData.address,
        commitHash: contractData.commitHash,
        etherscanUrl,
        filePath,
        displayAddress,
        displayEtherscanUrl,
        displayFilePathUrl,
      };

      category.sections[sectionIndex].contracts.push(contractInfo);
    }
  }

  // sort sections by name (Core contracts only)
  tableView.categories.core.sections = _.sortBy(
    tableView.categories.core.sections,
    ['name'],
  );

  // sort contracts by name (Core contracts only)
  tableView.categories.core.sections.forEach((section, i) => {
    tableView.categories.core.sections[i].contracts = _.sortBy(
      section.contracts,
      ['name'],
    );
  });

  return tableView;
}

function writeTables(deploymentPath: string, chain: string) {
  for (const key in tableView.categories) {
    const category = tableView.categories[key];

    let template = tableTemplate;
    let partial = detailedSummaryPartial;
    let pathKey = 'core';

    if (key === 'vaults' || key === 'optionReward' || key === 'optionPS') {
      if (chain === 'Arbitrum Nova') continue;
      template = tableTemplateNoHeader;
      partial = summaryPartial;
      pathKey = key;
    }

    // Generate md file from template
    let table = render(template, category, { partial });

    // Prettify table markdown
    table = prettier.format(table, { parser: 'markdown' });

    // Overwrite {pathKey}Table.md
    const tablePath = `${deploymentPath}/${pathKey}Table.md`;
    fs.writeFileSync(tablePath, table);
    console.log(`Table generated at ${tablePath}`);
  }
}

function inferContractName(
  contractKey: string,
  contractType: ContractType | string,
) {
  const override = NameOverride[contractKey];
  if (override) return override;

  let name = addSpaceBetweenUpperCaseLetters(contractKey);
  // remove the contract type from the name, if it's there
  const typeInName = name.split(' ').pop() === contractType;

  if (typeInName) return name.split(' ').slice(0, -1).join('');
  return name.split(' ').join('');
}

function inferContractDescription(
  contractKey: string,
  contractType: ContractType | string,
) {
  const override = DescriptionOverride[contractKey];
  if (override) return override;

  let name = addSpaceBetweenUpperCaseLetters(contractKey);
  // remove the contract type from the name, if it's there
  const typeInName = name.split(' ').pop() === contractType;

  if (typeInName) name = name.split(' ').slice(0, -1).join(' ');
  const type = addSpaceBetweenUpperCaseLetters(contractType);
  return `${name} ${type}`;
}

function addSpaceBetweenUpperCaseLetters(s: string) {
  return s.replace(/([a-z])([A-Z])/g, '$1 $2');
}
