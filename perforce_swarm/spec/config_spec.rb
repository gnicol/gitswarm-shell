require 'yaml'
require_relative 'spec_helper'
require_relative '../config'

describe PerforceSwarm::GitlabConfig do
  describe :git_fusion_entry do
    let(:config) { PerforceSwarm::GitlabConfig.new }

    context 'with default and other entries present' do
      before do
        config.instance_variable_set(:@config, YAML.load(<<eos
git_fusion:
  enabled: true
  some_value: some string
  default:
    url: "foo@bar"
  foo:
    url: "bar@baz"
  yoda:
    url: "http://foo@bar"
eos

                                                        )
                                    )
      end
      it 'loads the default config entry if one is present and no entry id is specified' do
        expect(config.git_fusion.entry['url']).to eq('foo@bar'), config.inspect
      end

      it 'loads the specified config entry by id' do
        expect(config.git_fusion.entry('foo')['url']).to eq('bar@baz'), config.inspect
      end

      it 'handles non-hash config entries' do
        expect(config.git_fusion['enabled']).to be_true, config.inspect
        expect(config.git_fusion['some_value']).to eq('some string'), config.inspect
      end

      it 'raises an exception if a specific entry id is requested by not found' do
        expect { config.git_fusion.entry('nonexistent') }.to raise_error(RuntimeError), config.inspect
      end
    end

    context 'no default entry' do
      before do
        config.instance_variable_set(:@config, YAML.load(<<eos
git_fusion:
  enabled: true
  foo:
    url: "bar@baz"
  bar:
    url: "baz@boop"
eos
                                                        )
                                    )
      end
      it 'loads the first configuration entry as the default one' do
        expect(config.git_fusion.entry(nil)['url']).to eq('bar@baz'), config.inspect
      end
    end

    context 'empty config' do
      before do
        config.instance_variable_set(:@config, git_fusion: {})
      end
      it 'raises an exception if no configuration is specified' do
        expect { config.git_fusion.entry }.to raise_error(RuntimeError), config.inspect
      end
      it 'defaults to disabled' do
        expect(config.git_fusion['enabled']).to be_false, config.inspect
      end
    end

    context 'nil config' do
      before do
        config.instance_variable_set(:@config, git_fusion: nil)
      end
      it 'raises an exception if the configuration is nil' do
        expect { config.git_fusion.entry }.to raise_error(RuntimeError), config.inspect
      end
      it 'defaults to disabled' do
        expect(config.git_fusion['enabled']).to be_false, config.inspect
      end
    end

    context 'invalid config' do
      before do
        config.instance_variable_set(:@config, git_fusion: 'one two three')
      end
      it 'raises an exception if an invalid configuration is given' do
        expect { config.git_fusion.entry }.to raise_error(RuntimeError), config.inspect
      end
      it 'defaults to disabled' do
        expect(config.git_fusion['enabled']).to be_false, config.inspect
      end
    end

    context 'entry contains no URL' do
      before do
        config.instance_variable_set(:@config, git_fusion: { foo: 'bar' })
      end
      it 'raises an exception if a config entry does not at least have a URL' do
        expect { config.git_fusion.entry }.to raise_error(RuntimeError), config.inspect
      end
      it 'defaults to disabled' do
        expect(config.git_fusion['enabled']).to be_false, config.inspect
      end
    end

    context 'no git_fusion entry' do
      before do
        config.instance_variable_set(:@config, {})
      end
      it 'raises an exception if no git_fusion config entry is found' do
        expect { config.git_fusion.entry }.to raise_error(RuntimeError), config.inspect
      end
      it 'defaults to disabled' do
        expect(config.git_fusion['enabled']).to be_false, config.inspect
      end
    end

    context 'with global block' do
      before do
        config.instance_variable_set(:@config, YAML.load(<<eos
git_fusion:
  enabled: true
  global:
    user: global-user
    password: global-password
    url: http://global-url
  foo:
    url: "bar@baz"
  bar:
    url: "baz@boop"
  luke:
    url: luke@tatooine
    user: luke
  vader:
    url: darth@thedeathstar
    user: darth
    password: thedarkside
  no-url:
    user: username
eos
                                             )
        )
      end
      it 'uses global settings when there are no entry-specific ones (default entry)' do
        entry = config.git_fusion.entry
        expect(entry['user']).to eq('global-user'), entry.pretty_inspect
        expect(entry['password']).to eq('global-password'), entry.pretty_inspect
        expect(entry['url']).to eq('bar@baz'), entry.pretty_inspect
      end
      it 'uses global settings when there are no entry-specific ones (specific entry)' do
        entry = config.git_fusion.entry('bar')
        expect(entry['user']).to eq('global-user'), entry.pretty_inspect
        expect(entry['password']).to eq('global-password'), entry.pretty_inspect
        expect(entry['url']).to eq('baz@boop'), entry.pretty_inspect
      end
      it 'uses specific settings when specified, even when globals exist' do
        entry = config.git_fusion.entry('vader')
        expect(entry['user']).to eq('darth'), entry.pretty_inspect
        expect(entry['password']).to eq('thedarkside'), entry.pretty_inspect
        expect(entry['url']).to eq('darth@thedeathstar'), entry.pretty_inspect
      end
      it 'uses entry-specific settings first, and globals when specific ones are not present' do
        entry = config.git_fusion.entry('luke')
        expect(entry['user']).to eq('luke'), entry.pretty_inspect
        expect(entry['password']).to eq('global-password'), entry.pretty_inspect
        expect(entry['url']).to eq('luke@tatooine'), entry.pretty_inspect
      end
      it 'returns nil for config parameters that are requested but do not exist' do
        entry = config.git_fusion.entry('luke')
        expect(entry['foo']).to be_nil, entry.pretty_inspect
      end
      it 'does not consider "global" to be a valid entry' do
        expect { config.git_fusion.entry('global') }.to raise_error(RuntimeError), config.inspect
      end
      it 'still considers entries with no URL to be invalid' do
        expect { config.git_fusion.entry('no-url') }.to raise_error(RuntimeError), config.inspect
      end
    end

    context 'with label values' do
      before do
        config.instance_variable_set(:@config, YAML.load(<<eos
git_fusion:
  enabled: true
  global:
    user: global-user
    password: global-password
    url: http://global-url
    label: Global label
  foo:
    url: "bar@baz"
    label: Default config entry called 'foo'
  bar:
    url: "baz@boop"
  luke:
    url: luke@tatooine
    user: luke
  vader:
    url: darth@thedeathstar
    user: darth
    password: thedarkside
    label: Death star plans are stored in this repo.
  no-url:
    user: username
eos
                                             )
        )
      end
      it 'allows a free-form string to be optionally used as a label for each block, ignoring global labels' do
        expect(config.git_fusion.entry['label']).to eq("Default config entry called 'foo'"), config.inspect
        expect(config.git_fusion.entry('bar')['label']).to be_nil, config.inspect
      end
    end
  end

  describe :fetch_worker do
    let(:config) { PerforceSwarm::GitlabConfig.new }
    context 'without fetch_worker settings' do
      before do
        config.instance_variable_set(:@config, YAML.load(<<eos
git_fusion:
  enabled: true
  some_value: some string
  default:
    url: "foo@bar"
  foo:
    url: "bar@baz"
  yoda:
    url: "http://foo@bar"
eos

                                             )
        )
        mock_config = PerforceSwarm::GitlabConfig
        mock_config.stub(:new).and_return(config)
      end
      it 'returns the default settings for fetch_worker configuration' do
        git_fusion_config = config.git_fusion
        expect(git_fusion_config.fetch_worker).to_not be_nil, git_fusion_config.inspect
        expect(git_fusion_config.fetch_worker['min_outdated']).to eq(300), git_fusion_config.inspect
        expect(git_fusion_config.fetch_worker['max_fetch_slots']).to eq(2), git_fusion_config.inspect
      end
    end
    context 'with fetch_worker settings' do
      before do
        config.instance_variable_set(:@config, YAML.load(<<eos
git_fusion:
  enabled: true
  some_value: some string
  fetch_worker:
    min_outdated: 600
  default:
    url: "foo@bar"
  foo:
    url: "bar@baz"
  yoda:
    url: "http://foo@bar"
eos

                                             )
        )
        mock_config = PerforceSwarm::GitlabConfig
        mock_config.stub(:new).and_return(config)
      end
      it 'returns the non-default settings for fetch_worker configuration' do
        git_fusion_config = config.git_fusion
        expect(git_fusion_config.fetch_worker).to_not be_nil, git_fusion_config.inspect
        expect(git_fusion_config.fetch_worker['min_outdated']).to eq(600), git_fusion_config.inspect
        expect(git_fusion_config.fetch_worker['max_fetch_slots']).to eq(2), git_fusion_config.inspect
      end
    end
  end

  describe :version_check do
    let(:config) { PerforceSwarm::GitlabConfig.new }
    context 'without global settings' do
      before do
        config.instance_variable_set(:@config, YAML.load(<<eos
git_fusion:
  enabled: true
  some_value: some string
  default:
    url: "foo@bar"
  foo:
    url: "bar@baz"
  yoda:
    url: "http://foo@bar"
eos

                                             )
        )
        mock_config = PerforceSwarm::GitlabConfig
        mock_config.stub(:new).and_return(config)
      end
      it 'doesnt validate version if none specified' do
        git_fusion = PerforceSwarm::GitFusion
        git_fusion.stub(:run).and_return('Rev. Git Fusion/2015.2/1128995 (2015/06/23)')
        current_config = config.git_fusion
        current_config.validate_entries.each do | instance, values |
          expect(values[:valid]).to be_true
          expect(values[:config]['url']).to eq(current_config[instance]['url'])
          expect(values[:version]).to eq('2015.2.1128995')
          expect(values[:outdated]).to be_nil
        end
      end

      it 'returns valid data and not outdated if version 2015.2' do
        git_fusion = PerforceSwarm::GitFusion
        git_fusion.stub(:run).and_return('Rev. Git Fusion/2015.2/1128995 (2015/06/23)')
        current_config = config.git_fusion
        current_config.validate_entries('2015.2').each do | instance, values |
          expect(values[:valid]).to be_true
          expect(values[:config]['url']).to eq(current_config[instance]['url'])
          expect(values[:version]).to eq('2015.2.1128995')
          expect(values[:outdated]).to be_false
        end
      end

      it 'returns non-valid and outdated if version < 2015.2' do
        git_fusion = PerforceSwarm::GitFusion
        git_fusion.stub(:run).and_return('Rev. Git Fusion/2015.1/142456 (2015/05/21)')
        config.git_fusion.validate_entries('2015.2').each do | _instance, values |
          expect(values[:valid]).to be_false
          expect(values[:version]).to eq('2015.1.142456')
          expect(values[:outdated]).to be_true
        end
      end

      it 'returns non-valid and outdated if we specified patch version' do
        git_fusion = PerforceSwarm::GitFusion
        git_fusion.stub(:run).and_return('Rev. Git Fusion/2015.1/121 (2015/05/21)')
        config.git_fusion.validate_entries('2015.2.122').each do | _instance, values |
          expect(values[:valid]).to be_false
          expect(values[:version]).to eq('2015.1.121')
          expect(values[:outdated]).to be_true
        end
      end

      it 'fails if version specified is not valid' do
        git_fusion = PerforceSwarm::GitFusion
        git_fusion.stub(:run).and_return('Rev. Git Fusion/2015.1/121 (2015/05/21)')
        expect { config.git_fusion.validate_entries('A2015/2/122') }
          .to raise_error(RuntimeError, 'Invalid min_version specified: A2015/2/122')
      end

      it 'returns error message caught from git command execution' do
        git_fusion = PerforceSwarm::GitFusion
        git_fusion.stub(:run).and_raise(PerforceSwarm::GitFusion::RunError, 'Very generic git error.')
        config.git_fusion.validate_entries('2015.2').each do | _instance, values |
          expect(values[:valid]).to be_false
          expect(values[:error]).to eq('Very generic git error.')
        end
      end
    end
  end
end
