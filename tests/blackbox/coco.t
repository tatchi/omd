Extra test not covered by the conformance tests
  $ enable_log=false omd_pp print /dev/stdin << "MD"
  > \## foo
  > MD
  \## foo

  $ enable_log=false omd_pp print /dev/stdin << "MD"
  > #\# foo
  > MD
  #\# foo

  $ enable_log=false omd << "MD"
  > #\# foo
  > MD
  <p>## foo</p>

  $ enable_log=false omd_pp print /dev/stdin << "MD"
  > \\## foo
  > MD
  \\## foo
  $ enable_log=false omd_pp print /dev/stdin << "MD"
  > \\\## foo
  > MD
  \\\## foo
  $ enable_log=false omd_pp print /dev/stdin << "MD"
  > \\\\## foo
  > MD
  \\\\## foo
  $ enable_log=false omd_pp print /dev/stdin << "MD"
  > ## helo
  > 
  > 
  > coucou
  > MD
  ## helo
  coucou

  $ enable_log=false omd << "MD"
  > \## foo
  > MD
  <p>## foo</p>

  $ enable_log=false omd << "MD"
  > \\## foo
  > MD
  <p>\## foo</p>

  $ enable_log=false omd << "MD"
  > \\\## foo
  > MD
  <p>\## foo</p>

  $ enable_log=false omd << "MD"
  > \\\\## foo
  > MD
  <p>\\## foo</p>

  $ enable_log=false omd << "MD"
  > <http://example.com?find=\*>
  > MD
  <p><a href="http://example.com?find=%5C*">http://example.com?find=\*</a></p>

  $ enable_log=false omd << "MD"
  > [http://example.com?find=\*](http://example.com?find=\*)
  > MD
  <p><a href="http://example.com?find=*">http://example.com?find=*</a></p>
