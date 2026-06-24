class Admin::Certification::YswsPolicy < ApplicationPolicy
  def index?
    user.admin? || user.has_role?(:guardian_of_integrity)
  end

  def show?
    user.can_review_ysws? && user.can_review_project_category?(record.try(:project))
  end

  def dashboard?
    index?
  end

  def update?
    show?
  end

  def report_fraud?
    show?
  end

  # Splits the review queue by reviewer subcategory: a regular Guardian of
  # Integrity sees only software reviews, a Hardware GOI only hardware reviews,
  # and admins (plus the dev nil bypass) see everything. "Hardware" is the
  # canonical Project#hardware? marker (hardware_stage present), not the
  # AI-classified project_type.
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all || user.admin?

      if user.hardware_guardian_of_integrity?
        scope.hardware
      elsif user.guardian_of_integrity?
        scope.non_hardware
      else
        scope.none
      end
    end
  end
end
