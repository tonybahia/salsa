module ApplicationHelper
  def salsa_partial(name, org=@organization)
    path_info = name.split '/'

    path = ''
    partial = name

    if path_info.size > 1 then
      partial = path_info.pop
      path = path_info.join('/') + '/'
    end

    view_folder = get_view_folder org

    #phase 2, make this dynamic?
    #dynamic scss/erb - http://microblog.anthonyestebe.com/2014-04-28/compile-your-scss-according-to-your-model-on-rails/
    #need a way to control who can do this though... or how much?

    # if this document is using a configuration and that configuration has the partial being requested, use it
    if org && org.components && org.components.find_by(slug: name)
      output = org.components.find_by(slug: name).layout
    # if there is a customized partial for this organization, use that
    elsif view_folder && File.exists?("app/views/#{view_folder}/#{path}_#{partial}.html.erb")
      output = render partial: "#{view_folder}/#{path}#{partial}"
    # do nothing (this allows there to be additional configs added that don't have a default)
    else
      output = ''
    end

    if output == ''
      # if there is a parent, recheck using it as the org
      if org.parent
        output = salsa_partial(name, org.parent)
      elsif org.slug.include? '/'
        output = salsa_partial(name, Organization.new(slug: org.slug.gsub(/\/[^\/]+$/, '')))
      # otherwise, show the default if it exists
      elsif File.exists?("app/views/instances/default/#{path}_#{partial}.html.erb")
        output = render partial: "instances/default/#{path}#{partial}"
      end
    end

    if output == '' && has_role('admin')
      output = "#{path}#{partial} does not exist"
    end

    return output.html_safe
  end

  def get_view_folder(org)
    # only update the view folder if the institution folder exists
    "instances/custom/#{org.slug}" if File.directory?("app/views/instances/custom/#{org.slug}")
  end

  def require_admin_password
    # if there is no admin password set up for the server and we are in the development
    # or test environment, bypass the securtiy check
    if !APP_CONFIG['admin_password'] && (Rails.env.development? || Rails.env.test?)
      session[:admin_authorized] = true
    elsif params[:admin_password] && params[:admin_password] != ''
      session[:admin_authorized] = params[:admin_password] == APP_CONFIG['admin_password']
    end

    if !has_role 'admin'
      redirect_to admin_login_path
    end
  end

  def has_role role
    result = false

    if role == 'admin'
      result = session[:admin_authorized]
    end

    result
  end

  def get_organizations
    # only show orgs that the logged in use should see
    unless session[:admin_authorized]
      # load all orgs that the user has a cascade == true assignment
      user = UserAssignment.find_by_username(
        session['canvas_access_token']['user']['id']
      ).user

      cascade_permissions = user.user_assignments.where(cascades: true)
      cascade_organizations = Organization.where(id: cascade_permissions.map(&:organization_id))

      filter_query = ['id IN (?)']
      filter_values = [user.user_assignments.map(&:organization_id)]

      cascade_organizations.each do |org|
        filter_query.push '(lft > ? AND rgt < ?)'
        filter_values.push org.lft
        filter_values.push org.rgt
      end

      filter_querystring = filter_query.join(' OR ')

      @organizations = Organization.where(filter_querystring, *filter_values)
    else
      @organizations = Organization.all.order(:lft, :rgt, :name)
    end
  end

  def full_org_path org
    if org[:depth] > 0 and org[:slug].start_with? '/'
      org_slug = org.self_and_ancestors.pluck(:slug).join ''
    else
      org_slug = org[:slug]
    end

    org_slug
  end

  def org_slug_parts org
    org_slug = full_org_path(org)

    if org_slug
      parts = org_slug.split '/', 2
    end

    parts = ['', ''] unless parts

    parts
  end

  def find_org_by_path path
    unless path.include? '/'
      organization = Organization.find_by! slug:path
    else
      path.split('/').each do |slug|
        unless organization
          organization = Organization.find_by! slug: slug, depth: 0
        else
          organization = organization.children.find_by! slug: "/" + slug
        end
      end
    end

    organization
  end

  def redirect_port
    ':' + request.env['SERVER_PORT'] unless ['80', '443'].include?(request.env['SERVER_PORT'])
  end
end
