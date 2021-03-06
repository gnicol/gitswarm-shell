module PerforceSwarm
  module P4
    module Spec
      class User
        # Create the specified user. If the user already exists they will be updated with any modified 'extra' details.
        def self.create(connection, id, extra = {})
          connection.input = connection.run(*%W(user -o #{id})).last
          # P4::Spec returned by 'last' subclasses Hash, if we merge! in extra then
          # this bypasses the validation that would be carried out on permitted
          # fields and they would simply get ignored. Running spec[<field>] = <value>
          # causes validation to happen with P4Exception: Invalid field raised for
          # errors
          extra.each do |key, value|
            connection.input[key] = value
          end
          connection.run(*%w(user -i -f))
        end

        # Give the specified user the specified privilege.
        # Note this requires a super user level connection
        def self.add_privilege(connection, id, privilege, path)
          protections = connection.run(*%w(protect -o)).last
          protections['Protections'].push("#{privilege} user #{id} * #{path}")
          connection.input = protections
          connection.run(*%w(protect -i))
        end

        # Sets the P4D password for the specified user. Not used to update the connected user's password.
        # Note this requires a super user level connection.
        def self.set_password(connection, id, password)
          connection.input = "#{password}"
          connection.run(*%W(passwd #{id}))
        end
      end
    end
  end
end
