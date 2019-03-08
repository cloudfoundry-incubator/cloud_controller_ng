require 'spec_helper'

module VCAP::CloudController
  RSpec.describe AppModel do
    let(:app_model) { AppModel.create(space: space, name: 'some-name') }
    let(:space) { FactoryBot.create(:space) }

    describe '#oldest_web_process' do
      context 'when there are no web processes' do
        it 'returns nil' do
          expect(app_model.oldest_web_process).to be_nil
        end
      end

      context 'when there are multiple web processes' do
        let!(:web_process) do
          VCAP::CloudController::ProcessModel.make(
            app: app_model,
            command: 'old command!',
            instances: 3,
            type: VCAP::CloudController::ProcessTypes::WEB,
            created_at: Time.now - 24.hours
          )
        end
        let!(:newer_web_process) do
          VCAP::CloudController::ProcessModel.make(
            app: app_model,
            command: 'new command!',
            instances: 4,
            type: VCAP::CloudController::ProcessTypes::WEB,
            created_at: Time.now - 23.hours
          )
        end

        it 'returns the oldest one' do
          expect(app_model.oldest_web_process).to eq(web_process)
        end
      end
    end

    describe '#newest_web_process' do
      context 'when there are no web processes' do
        it 'returns nil' do
          expect(app_model.oldest_web_process).to be_nil
        end
      end

      context 'when there are multiple web processes' do
        let(:created_at_for_new_processes) { Time.now - 23.hours }

        let!(:web_process) do
          VCAP::CloudController::ProcessModel.make(
            app: app_model,
            command: 'old command!',
            instances: 3,
            type: VCAP::CloudController::ProcessTypes::WEB,
            created_at: Time.now - 24.hours
          )
        end
        let!(:newer_web_process) do
          VCAP::CloudController::ProcessModel.make(
            app: app_model,
            command: 'new command!',
            instances: 4,
            type: VCAP::CloudController::ProcessTypes::WEB,
            created_at: created_at_for_new_processes
          )
        end
        let!(:most_newest_web_process) do
          VCAP::CloudController::ProcessModel.make(
            app: app_model,
            command: 'new command!',
            instances: 4,
            type: VCAP::CloudController::ProcessTypes::WEB,
            created_at: created_at_for_new_processes
          )
        end

        it 'returns the newest one' do
          expect(app_model.newest_web_process).to eq(most_newest_web_process)
          expect(newer_web_process.id).to be < most_newest_web_process.id
        end
      end
    end

    describe '#latest_revision' do
      let!(:revision1) { RevisionModel.make(app: app_model, created_at: 10.minutes.ago) }
      let!(:revision2) { RevisionModel.make(app: app_model) }
      let!(:revision3) { RevisionModel.make(app: app_model, created_at: 5.minutes.ago) }

      context 'when revisions are enabled' do
        before do
          app_model.update(revisions_enabled: true)
        end

        it 'returns the newest one' do
          expect(app_model.latest_revision).to eq(revision2)
        end

        context 'when two were created in the same second' do
          let!(:revision4) { RevisionModel.make(app: app_model, created_at: revision2.created_at) }

          it 'prefers the one with the higher id' do
            expect(app_model.latest_revision).to eq(revision4)
          end
        end
      end

      context 'when revisions are not enabled' do
        before do
          app_model.update(revisions_enabled: false)
        end

        it 'returns nil' do
          expect(app_model.latest_revision).to be_nil
        end
      end
    end

    describe '#can_create_revision' do
      let!(:app_model) { AppModel.make(space: space, name: 'some-name', desired_state: ProcessModel::STARTED) }
      let!(:process1) { ProcessModel.make(:process, app: app_model, type: 'web', command: 'webby') }
      let!(:process2) { ProcessModel.make(:process, app: app_model, type: 'worker') }
      let!(:droplet) { DropletModel.make(app: app_model, process_types: { 'web': 'webby', 'worker': nil }) }
      let!(:environment_variables) { {} }

      before do
        app_model.update(revisions_enabled: true, droplet_guid: droplet.guid, environment_variables: environment_variables)
      end

      context 'when there are revisions associated with the app' do
        let!(:revision) do
          revis = RevisionModel.make(
            app: app_model,
            droplet_guid: droplet.guid,
            environment_variables: environment_variables,
          )
          RevisionProcessCommandModel.create(revision_guid: revis.guid, process_type: 'web', process_command: 'webby')
        end

        it 'returns false when nothing has changed' do
          expect(app_model.can_create_revision?).to be_falsey
        end

        context 'when droplet on the latest revision is different than the apps desired droplet' do
          let!(:droplet2) { DropletModel.make(app: app_model, process_types: { 'web': 'webby', 'worker': nil }) }

          before do
            app_model.update(droplet: droplet2)
          end

          it 'returns true' do
            expect(app_model.can_create_revision?).to be_truthy
          end
        end

        context 'when env vars on the latest revision is different than the apps env vars' do
          before do
            app_model.update(environment_variables: { 'something' => 'different' })
          end

          it 'returns true' do
            expect(app_model.can_create_revision?).to be_truthy
          end
        end

        context 'when commands on the latest revision are different than the apps processes commands' do
          before do
            process1.update(command: 'dont start')
          end

          it 'returns true' do
            expect(app_model.can_create_revision?).to be_truthy
          end
        end
      end

      context 'when there are no revisions associated with the app' do
        it 'returns true' do
          expect(app_model.can_create_revision?).to be_truthy
        end
      end

      context 'when revisions are not enabled' do
        before do
          app_model.update(revisions_enabled: false)
        end

        it 'returns false' do
          expect(app_model.can_create_revision?).to be_falsey
        end
      end
    end

    describe '#staging_in_progress' do
      context 'when a build is in staging state' do
        let!(:build) { BuildModel.make(app_guid: app_model.guid, state: BuildModel::STAGING_STATE) }

        it 'returns true' do
          expect(app_model.staging_in_progress?).to eq(true)
        end
      end

      context 'when a build is not in neither pending or staging state' do
        let!(:build) { BuildModel.make(app_guid: app_model.guid, state: BuildModel::STAGED_STATE) }

        it 'returns false' do
          expect(app_model.staging_in_progress?).to eq(false)
        end
      end
    end

    describe 'fields' do
      describe 'max_task_sequence_id' do
        it 'defaults to 0' do
          expect(app_model.max_task_sequence_id).to eq(1)
        end
      end
    end

    describe '#destroy' do
      context 'when the app has buildpack_lifecycle_data' do
        subject(:lifecycle_data) do
          BuildpackLifecycleDataModel.create(buildpacks: ['http://some-buildpack.com', 'http://another-buildpack.net'])
        end

        it 'destroys the buildpack_lifecycle_data and associated buildpack_lifecycle_buildpacks' do
          app_model.update(buildpack_lifecycle_data: lifecycle_data)
          expect {
            app_model.destroy
          }.to change { BuildpackLifecycleDataModel.count }.by(-1).
            and change { BuildpackLifecycleBuildpackModel.count }.by(-2)
        end
      end
    end

    describe 'validations' do
      it { is_expected.to strip_whitespace :name }

      describe 'name' do
        let(:space_guid) { space.guid }
        let(:app) { AppModel.make }

        it 'uniqueness is case insensitive' do
          AppModel.make(name: 'lowercase', space_guid: space_guid)

          expect {
            AppModel.make(name: 'lowerCase', space_guid: space_guid)
          }.to raise_error(Sequel::ValidationFailed, 'name must be unique in space')
        end

        it 'should allow standard ascii characters' do
          app.name = "A -_- word 2!?()\'\"&+."
          expect {
            app.save
          }.to_not raise_error
        end

        it 'should allow backslash characters' do
          app.name = 'a \\ word'
          expect {
            app.save
          }.to_not raise_error
        end

        it 'should allow unicode characters' do
          app.name = '防御力¡'
          expect {
            app.save
          }.to_not raise_error
        end

        it 'should not allow newline characters' do
          app.name = "a \n word"
          expect {
            app.save
          }.to raise_error(Sequel::ValidationFailed)
        end

        it 'should not allow escape characters' do
          app.name = "a \e word"
          expect {
            app.save
          }.to raise_error(Sequel::ValidationFailed)
        end
      end

      describe 'name is unique within a space' do
        it 'name can be reused in different spaces' do
          name = 'zach'

          space1 = FactoryBot.create(:space)
          space2 = FactoryBot.create(:space)

          AppModel.make(name: name, space_guid: space1.guid)
          expect {
            AppModel.make(name: name, space_guid: space2.guid)
          }.not_to raise_error
        end

        it 'name is unique in the same space' do
          name = 'zach'

          space = FactoryBot.create(:space)

          AppModel.make(name: name, space_guid: space.guid)

          expect {
            AppModel.make(name: name, space_guid: space.guid)
          }.to raise_error(Sequel::ValidationFailed, 'name must be unique in space')
        end
      end

      describe 'environment_variables' do
        it 'validates them' do
          expect {
            AppModel.make(environment_variables: '')
          }.to raise_error(Sequel::ValidationFailed, /must be a hash/)
        end
      end

      describe 'droplet' do
        let(:droplet) { DropletModel.make(app: app_model) }

        it 'does not allow droplets that are not STAGED' do
          states = DropletModel::DROPLET_STATES - [DropletModel::STAGED_STATE]
          states.each do |state|
            droplet.state = state
            expect {
              app_model.droplet = droplet
              app_model.save
            }.to raise_error(Sequel::ValidationFailed, /must be in staged state/)
          end
        end

        it 'is valid with droplets that are STAGED' do
          droplet.state = DropletModel::STAGED_STATE
          app_model.droplet = droplet
          expect(app_model).to be_valid
        end
      end
    end

    describe '#lifecycle_type' do
      context 'the model contains buildpack_lifecycle_data' do
        before { FactoryBot.create(:buildpack_lifecycle_data, app: app_model) }

        it 'returns the string "buildpack" if buildpack_lifecycle_data is on the model' do
          expect(app_model.lifecycle_type).to eq('buildpack')
        end
      end

      context 'the model does not contain buildpack_lifecycle_data' do
        before do
          app_model.buildpack_lifecycle_data = nil
          app_model.save
        end

        it 'returns the string "docker" if buildpack_lifecycle data is not on the model' do
          expect(app_model.lifecycle_type).to eq('docker')
        end
      end
    end

    describe '#lifecycle_data' do
      let!(:lifecycle_data) { FactoryBot.create(:buildpack_lifecycle_data, app: app_model) }

      it 'returns buildpack_lifecycle_data if it is on the model' do
        expect(app_model.lifecycle_data).to eq(lifecycle_data)
      end

      it 'is a persistable hash' do
        expect(app_model.reload.lifecycle_data.buildpacks).to eq(lifecycle_data.buildpacks)
        expect(app_model.reload.lifecycle_data.stack).to eq(lifecycle_data.stack)
      end

      context 'buildpack_lifecycle_data is nil' do
        let(:non_buildpack_app_model) { AppModel.create(name: 'non-buildpack', space: space) }

        it 'returns a docker data model' do
          expect(non_buildpack_app_model.lifecycle_data).to be_a(DockerLifecycleDataModel)
        end
      end
    end

    describe '#database_uri' do
      let(:parent_app) { AppModel.make(environment_variables: { 'jesse' => 'awesome' }, space: space) }
      let(:process) { ProcessModel.make(app: parent_app) }

      context 'when there are database-like services' do
        before do
          sql_service_plan     = ServicePlan.make(service: Service.make(label: 'elephantsql-n/a'))
          sql_service_instance = ManagedServiceInstance.make(space: space, service_plan: sql_service_plan, name: 'elephantsql-vip-uat')
          ServiceBinding.make(app: parent_app, service_instance: sql_service_instance, credentials: { 'uri' => 'mysql://foo.com' })

          banana_service_plan     = ServicePlan.make(service: Service.make(label: 'chiquita-n/a'))
          banana_service_instance = ManagedServiceInstance.make(space: space, service_plan: banana_service_plan, name: 'chiqiuta-yummy')
          ServiceBinding.make(app: parent_app, service_instance: banana_service_instance, credentials: { 'uri' => 'banana://yum.com' })
        end

        it 'returns database uri' do
          expect(process.reload.database_uri).to eq('mysql2://foo.com')
        end
      end

      context 'when there are non-database-like services' do
        before do
          banana_service_plan     = ServicePlan.make(service: Service.make(label: 'chiquita-n/a'))
          banana_service_instance = ManagedServiceInstance.make(space: space, service_plan: banana_service_plan, name: 'chiqiuta-yummy')
          ServiceBinding.make(app: parent_app, service_instance: banana_service_instance, credentials: { 'uri' => 'banana://yum.com' })

          uncredentialed_service_plan     = ServicePlan.make(service: Service.make(label: 'mysterious-n/a'))
          uncredentialed_service_instance = ManagedServiceInstance.make(space: space, service_plan: uncredentialed_service_plan, name: 'mysterious-mystery')
          ServiceBinding.make(app: parent_app, service_instance: uncredentialed_service_instance, credentials: {})
        end

        it 'returns nil' do
          expect(process.reload.database_uri).to be_nil
        end
      end

      context 'when there are no services' do
        it 'returns nil' do
          expect(process.reload.database_uri).to be_nil
        end
      end

      context 'when the service binding credentials is nil' do
        before do
          banana_service_plan     = ServicePlan.make(service: Service.make(label: 'chiquita-n/a'))
          banana_service_instance = ManagedServiceInstance.make(space: space, service_plan: banana_service_plan, name: 'chiqiuta-yummy')
          ServiceBinding.make(app: parent_app, service_instance: banana_service_instance, credentials: nil)
        end

        it 'returns nil' do
          expect(process.reload.database_uri).to be_nil
        end
      end
    end

    describe 'default enable_ssh' do
      context 'when enable_ssh is set explicitly' do
        it 'does not overwrite it with the default' do
          app1 = AppModel.make(enable_ssh: true)
          expect(app1.enable_ssh).to eq(true)

          app2 = AppModel.make(enable_ssh: false)
          expect(app2.enable_ssh).to eq(false)
        end
      end

      context 'when default_app_ssh_access is true' do
        before do
          TestConfig.override({ default_app_ssh_access: true })
        end

        it 'sets enable_ssh to true' do
          app = AppModel.make
          expect(app.enable_ssh).to eq(true)
        end
      end

      context 'when default_app_ssh_access is false' do
        before do
          TestConfig.override({ default_app_ssh_access: false })
        end

        it 'sets enable_ssh to false' do
          app = AppModel.make
          expect(app.enable_ssh).to eq(false)
        end
      end
    end

    describe '#user_visibility_filter' do
      let!(:other_app) { AppModel.make }

      context "when a user is a developer in the app's space" do
        let(:user) { make_developer_for_space(app_model.space) }

        it 'the service binding is visible' do
          expect(AppModel.user_visible(user).all).to eq [app_model]
        end
      end

      context "when a user is an auditor in the app's space" do
        let(:user) { make_auditor_for_space(app_model.space) }

        it 'the service binding is visible' do
          expect(AppModel.user_visible(user).all).to eq [app_model]
        end
      end

      context "when a user is an org manager in the app's space" do
        let(:user) { make_manager_for_org(app_model.space.organization) }

        it 'the service binding is visible' do
          expect(AppModel.user_visible(user).all).to eq [app_model]
        end
      end

      context "when a user is a space manager in the app's space" do
        let(:user) { make_manager_for_space(app_model.space) }

        it 'the service binding is visible' do
          expect(AppModel.user_visible(user).all).to eq [app_model]
        end
      end

      context "when a user has no visibility to the app's space" do
        let(:user) { User.make }

        it 'the service binding is not visible' do
          expect(AppModel.user_visible(user).all).to be_empty
        end
      end
    end

    describe '#current_package' do
      context 'when the app has a current droplet assigned' do
        let(:package) { PackageModel.make }

        before do
          app_model.update(droplet: DropletModel.make(package: package))
        end

        it 'returns the package from the current droplet' do
          expect(app_model.current_package).to eq(package)
        end
      end

      context 'when the app does not have a current droplet assigned' do
        it 'returns nil' do
          expect(app_model.current_package).to be_nil
        end
      end
    end

    describe '#deploying?' do
      it 'returns false when the app has no deployments' do
        expect(app_model.deploying?).to be(false)
      end

      it 'returns false when the app has no deployments that are being deployed' do
        VCAP::CloudController::DeploymentModel.make(state: 'DEPLOYED', app: app_model)
        VCAP::CloudController::DeploymentModel.make(state: 'CANCELING', app: app_model)
        VCAP::CloudController::DeploymentModel.make(state: 'CANCELED', app: app_model)

        expect(app_model.deploying?).to be(false)
      end

      it 'returns true when the app has a deployment that is being deployed' do
        VCAP::CloudController::DeploymentModel.make(state: 'DEPLOYED', app: app_model)
        VCAP::CloudController::DeploymentModel.make(state: 'CANCELING', app: app_model)
        VCAP::CloudController::DeploymentModel.make(state: 'DEPLOYING', app: app_model)
        VCAP::CloudController::DeploymentModel.make(state: 'CANCELED', app: app_model)

        expect(app_model.deploying?).to be(true)
      end
    end
  end
end
