class Role < ApplicationRecord
  belongs_to :person, required: true
  belongs_to :scope, polymorphic: true, optional: true

  validates :person_id, uniqueness: { scope: [:role_type_id, :scope_id, :scope_type] }
  validates :role_type, presence: true
  validate :role_type_matches_scope, if: -> { role_type.present? }
  validate :scope_allows_person, if: -> { scope.present? }

  delegate :key, to: :role_type

  after_commit :queue_update_auth_table
  enforce_authorization_on_association :person, :manage

  def self.with_role_key(key)
    role_type = RoleType.find_by_key(key)
    raise Seek::Roles::UnknownRoleException, "Unknown role '#{key}'" unless role_type
    where(role_type_id: role_type)
  end

  def role_type
    RoleType.find_by_id(role_type_id)
  end

  def role_type=(record_or_key)
    self.role_type_id = (record_or_key.is_a?(RoleType) ? record_or_key : RoleType.find_by_key(record_or_key)).id
  end

  def scope_title
    I18n.t(scope.nil? ? 'roles.scopes.system' : scope_type.underscore)
  end

  private

  def role_type_matches_scope
    if scope&.class&.name != role_type.scope
      errors.add(:role_type, "is not a valid #{scope_title} role.")
    end
  end

  def scope_allows_person
    if scope.is_a?(Project) && !scope.people.include?(person)
      errors.add(:person, "does not belong to this #{scope_title}.")
    end
  end

  def queue_update_auth_table
    AuthLookupUpdateQueue.enqueue(person) if person
  end
end
