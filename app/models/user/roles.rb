module User::Roles
  extend ActiveSupport::Concern

  included do
    User::Role.all_slugs.each do |role_name|
      define_method "#{role_name}?" do
        has_role?(role_name)
      end
    end
  end

  def roles = granted_roles&.map(&:to_sym) || []

  def has_role?(role_name) = roles.include?(role_name.to_sym)

  def admin? = has_role?(:admin) || has_role?(:super_admin)

  def can_review? = admin? || has_role?(:project_certifier)

  # Either kind of Guardian of Integrity: the regular role or the hardware
  # subcategory. Excludes plain admins (who can see everything but aren't GOIs).
  def guardian_of_integrity_any? = has_role?(:guardian_of_integrity) || has_role?(:hardware_guardian_of_integrity)

  # Who may reach the YSWS review queue: admins and both GOI subcategories. The
  # queue is then split by category — regular GOI sees software, hardware GOI
  # sees hardware — in Admin::Certification::YswsPolicy::Scope.
  def can_review_ysws? = admin? || guardian_of_integrity_any?

  # Whether this reviewer may act on a project of the given category. Admins see
  # everything; a Hardware GOI is confined to hardware projects, a regular GOI
  # to software. Keeps the queue split (YswsPolicy::Scope) and every member
  # action (YSWS review, devlog review, devlog commits) consistent. A nil
  # project can't be categorised, so it's allowed (the controller handles it).
  def can_review_project_category?(project)
    return true if admin?
    return true if project.nil?

    if has_role?(:hardware_guardian_of_integrity)
      project.hardware?
    elsif has_role?(:guardian_of_integrity)
      !project.hardware?
    else
      false
    end
  end

  def can_nominate_super_star? = can_review? || guardian_of_integrity_any?

  def can_see_deleted_devlogs? = admin? || has_role?(:fraud_dept)

  def highest_role
    roles.min_by { |role| User::Role.all_slugs.index(role) }&.to_s&.titleize || "User"
  end

  def grant_role!(role_name)
    role = role_name.to_sym
    raise ArgumentError, "Invalid role: #{role_name}" unless User::Role.all_slugs.include?(role)

    return if has_role?(role)

    update!(granted_roles: roles + [ role ])
    notify_role_granted(role)
  end

  def remove_role!(role_name)
    role = role_name.to_sym
    raise ArgumentError, "Invalid role: #{role_name}" unless User::Role.all_slugs.include?(role)

    update!(granted_roles: roles - [ role ]) if has_role?(role)
  end

  private

    def notify_role_granted(role)
      return if Rails.env.development?
      return unless slack_id.present?

      role_info = User::Role.find(role)
      message = "Congratulations! You've been granted the *#{role_info.name.to_s.titleize}* role on Stardance."
      dm_user(message)
    end
end
