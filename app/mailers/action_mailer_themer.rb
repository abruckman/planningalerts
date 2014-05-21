module ActionMailerThemer

  private

  def themed_mail(params)
    theme = params.delete(:theme)

    # TODO Extract this into the theme
    if theme == "default"
      template_path = mailer_name
    elsif theme == "nsw"
      template_path = ["../../lib/themes/#{theme}/views/#{mailer_name}", mailer_name]
      self.prepend_view_path "lib/themes/#{theme}/views"
    else
      raise "Unknown theme #{theme}"
    end

    @host = ThemeChooser.create(theme).host

    mail(params.merge(template_path: template_path))
  end

  def email_from(theme)
    ThemeChooser.create(theme).email_from
  end
end