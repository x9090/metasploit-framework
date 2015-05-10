require 'spec_helper'
require 'msf/core/exe/segment_injector'

describe Msf::Exe::SegmentInjector do

  let(:opts) do
    option_hash = {
        :template => File.join(File.dirname(__FILE__), "..", "..", "..", "..", "..", "data", "templates", "template_x86_windows.exe"),
        :payload  => "\xd9\xeb\x9b\xd9\x74\x24",
        :arch     => :x86
    }
  end
  subject(:injector) { Msf::Exe::SegmentInjector.new(opts) }

  it { should respond_to :payload }
  it { should respond_to :template }
  it { should respond_to :arch }
  it { should respond_to :processor }
  it { should respond_to :buffer_register }

  it 'should return the correct processor for the arch' do
    injector.processor.class.should == Metasm::Ia32
    injector.arch = :x64
    injector.processor.class.should == Metasm::X86_64
  end

  context '#create_thread_stub' do
    it 'should use edx as a default buffer register' do
      injector.buffer_register.should == 'edx'
    end

    context 'when given a non-default buffer register' do
      let(:opts) do
        option_hash = {
            :template => File.join(File.dirname(__FILE__), "..", "..", "..", "..", "..", "data", "templates", "template_x86_windows.exe"),
            :payload  => "\xd9\xeb\x9b\xd9\x74\x24",
            :arch     => :x86,
            :buffer_register => 'eax'
        }
      end
      it 'should use the correct buffer register' do
        injector.buffer_register.should == 'eax'
      end
    end

    it 'should set a buffer register for the payload' do
      injector.create_thread_stub.should include('lea edx, [thread_hook]')
    end
  end

  describe '#generate_pe' do
    it 'should return a string' do
      injector.generate_pe.kind_of?(String).should == true
    end

    it 'should produce a valid PE exe' do
      expect {Metasm::PE.decode(injector.generate_pe) }.to_not raise_exception
    end

    context 'the generated exe' do
      let(:exe) { Metasm::PE.decode(injector.generate_pe) }
      it 'should be the propper arch' do
        exe.bitsize.should == 32
      end

      it 'should have 5 sections' do
        exe.sections.count.should == 5
      end

      it 'should have all the right section names' do
        s_names = []
        exe.sections.collect {|s| s_names << s.name}
        s_names.should == [".text", ".rdata", ".data", ".rsrc", ".text"]
      end

      it 'should have the last section set to RWX' do
        exe.sections.last.characteristics.should == ["CONTAINS_CODE", "MEM_EXECUTE", "MEM_READ", "MEM_WRITE"]
      end

      it 'should have an entrypoint that points to the last section' do
        exe.optheader.entrypoint.should == exe.sections.last.virtaddr
      end
    end
  end
end

