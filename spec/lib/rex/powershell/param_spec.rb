# -*- coding:binary -*-
require 'spec_helper'

require 'rex/powershell'

describe Rex::Powershell::Param do

  let(:param_name) do
    Rex::Text.rand_text_alpha(15)
  end

  let(:klass_name) do
    Rex::Text.rand_text_alpha(15)
  end

  describe "::initialize" do
    it 'should create a param' do
      param = Rex::Powershell::Param.new(klass_name, param_name)
      param.should be
      param.name.should eq param_name
      param.klass.should eq klass_name
      param.to_s.include?("[#{klass_name}]$#{param_name}").should be_truthy
    end
  end

end

