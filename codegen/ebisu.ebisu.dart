import "dart:io";
import "package:path/path.dart" as path;
import "package:ebisu/ebisu.dart";
import "package:id/id.dart";
import "package:ebisu/ebisu_dart_meta.dart";
import "package:ebisu/ebisu_compiler.dart";
import "package:logging/logging.dart";

String _topDir;

void main() {

  //////////////////////////////////////////////////////////////////////
  // Uncomment following for logging
  // Logger.root.onRecord.listen((LogRecord r) =>
  //    print("${r.loggerName} [${r.level}]:\t${r.message}"));

  Options options = new Options();
  String here = path.absolute(options.script);
  bool noCompile = options.arguments.contains('--no_compile');
  bool compileOnly = options.arguments.contains('--compile_only');
  _topDir = path.dirname(path.dirname(here));
  String templateFolderPath = 
    path.join(_topDir, 'lib', 'templates', 'dart_meta');
  if(! (new Directory(templateFolderPath).existsSync())) {
    throw new StateError(
        "Could not find ebisu templates in $templateFolderPath");
  }

  if(!noCompile) {
    TemplateFolder templateFolder = new TemplateFolder(templateFolderPath);
    int filesUpdated = templateFolder.compile();
    if(filesUpdated>0) {
      if(!noCompile && !compileOnly) {
        // Files were updated, since Dart does not have eval, call again to same
        // script using updated templates
        print("$filesUpdated files updated...rerunning");
        List<String> args = [ options.script, '--no_compile' ]
          ..addAll(options.arguments);
        print("Args are " + args.toString());
        Process.run('run_dart.dart', args).then((ProcessResult results) {
          print(results.stdout);
          print(results.stderr);
        });
      }
    } else {
      if(!compileOnly)
        generate();
    }
  } else {
    generate();
  }
}

generate() {

  Library ebisu_compiler = library('ebisu_compiler');
  ebisu_compiler..doc = '''

Supports generating dart code from template files.  A choice had to be made
about a templating system. Originally dart had a library to support templates
but it was later abandoned in preference for a new approach (_Web UI_) that does
much more than just templating as it is a very web specific solution. Mustache
is another good option, but for code generation the arguments for separating
templates and logic fall apart (the coders are the ones writing the templates to
make their life of coding easier). Rather than try to incorporate one in NIH/DIY
fashion a very simple template engine is provided here. The rules for templating
are simple:

- Template file is line based (each line is a comment, code or template text)
- _#<# dart comment here >_
- _#< dart code here >_
- All template text is wrapped in tripple quotes.


'''
    ..includeLogger = true
    ..imports = [
      'io',
      '"package:ebisu/ebisu.dart"',
      '"package:ebisu/ebisu_dart_meta.dart"',
      '"package:path/path.dart" as path',
    ]
    ..variables = [
      variable('code_re')
      ..doc = 'Regex to match a single line if dart code (i.e. in looks like #< ... >)'
      ..type = 'RegExp'
      ..isFinal = true
      ..init = r'new RegExp("^#<(.*)>\\s*")',
      variable('comment_re')
      ..doc = 'Regex to match the comment portion of a comment line (i.e. in looks like #<# ... >)'
      ..type = 'RegExp'
      ..isFinal = true
      ..init = r'new RegExp("^\\s*#")',
    ]
    ..parts = [
      part('compiler')
      ..classes = [
        class_('template_file')
        ..doc = 'A file with ".tmpl" extension containing mixed dart code and text that can be "realized" by the template engine'
        ..ctorSansNew = true
        ..members = [
          member('input_path')
          ..doc = 'Path to file containting template code'
          ..ctors = [ '' ],
          member('output_path')
          ..doc = 'Path to write the supporting dart file for the template'
          ..ctorsNamed = [ '' ],
          member('part_of')
          ..doc = 'Name of library this "part" is a part of'
          ..ctorsNamed = [ '' ],
          member('function_name')
          ..doc = 'Each file is given a corresponding top level function for running the template'
          ..access = Access.RO
        ],
        class_('template_folder')
        ..doc = '''A class to process a folder full of templates, 
all of which get compiled into a single dart library'''
        ..members = [
          member('input_path')
          ..doc = 'Path to folder of templates'
          ..ctors = [ 'default' ],
          member('output_path')
          ..ctorsOpt = [ 'default' ]
          ..doc = 'Path to write the supporting dart files for the template folder',
          member('lib_name')
          ..ctorsOpt = [ 'default' ]
          ..doc = 'Name of dart library to be generated',
          member('imports')
          ..doc = 'List of imports required by the generated dart library'
          ..type = 'List<String>'
          ..classInit = '[]',
        ]
      ]
    ];

  Library ebisu_utils = library('ebisu_utils')
    ..imports = [ 'math', "'dart:convert' as convert" ]
    ..includeLogger = true
    ..doc = 'Support code to be used by libraries generated with ebisu. Example (toJson)';

  // The following are commonly used members of the meta data classes
  Member doc_member(String owner) => member('doc')
    ..doc = "Documentation for this $owner";

  Member public_member(String owner) => member('is_public')
    ..doc = "True if $owner is public.\nCode generation support will prefix private variables appropriately"
    ..type = 'bool'
    ..classInit = 'true';

  Member id_member(String owner) => member('id')
    ..doc = "Id for this $owner"
    ..type = 'Id'
    ..access = Access.RO
    ..ctors = ['']
    ..isFinal = true;

  Member non_final_id_member(String owner) => member('id')
    ..doc = "Id for this $owner"
    ..type = 'Id'
    ..access = Access.RO;

  Member parent_member(String owner) => member('parent')
    ..doc = "Reference to parent of this $owner"
    ..type = 'dynamic'
    ..jsonTransient = true
    ..access = Access.RO;

  Member custom_member(String owner) => member('include_custom')
    ..doc = "If true a custom section will be included for $owner"
    ..type = 'bool'
    ..classInit = 'true';

  Library ebisu_dart_meta = library('ebisu_dart_meta')
    ..doc = '''

Support for storing dart meta data for purpose of generating code. Essentially
this is a model of structural code items that comprise dart systems. Things like
libraries (Library), classes (Class), class members (Member), pubspecs
(PubSpec), etc. A very nice feature of Dart is the dot-dot _.._ operator, which
allows one to conveniently string together accessor calls to objects. For
example, the following is the structure of the imported id library.

      library('id')
      ..doc = '...'
      ..includeLogger = true
      ..imports = [
        'dart:convert'
      ]
      ..classes = [
        class_('id')
        ..doc = "Given an id (all lower case string of words separated by '_')..."
        ..ctorSansNew = true
        ..members = [
          member('id')
          ..doc = "String containing the lower case words separated by '_'"
          ..access = Access.RO
          ..isFinal = true,
          member('words')
          ..doc = "Words comprising the id"
          ..type = 'List<String>'
          ..access = Access.RO
          ..isFinal = true
        ]
      ]
    ];


The libraries are composed into a system and the system is generated. So, all
the code structure in ebisu was generated by itself. Code generation of this
sort is much more useful in the more verbose languages like C++ where things
like ORM, object serialization, object streaming etc are very
boilerplate. However some good use cases exist in Dart, like generating the
structure of a large Dart library from an existing spec or data input
(e.g. imagine trying to create a Dart library to support a FIX specification
which is stored in XML). A simple use that is provided as an extension is the
ability take a simple Altova UML model in XMI format and convert it to Dart
classes with JSON support.

'''
    ..imports = [
      'io', '"dart:convert" as convert', 
      '"package:ebisu/ebisu.dart"', 
      '"package:id/id.dart"', 
      '"package:ebisu/ebisu_utils.dart" as ebisu_utils', 
      '"templates/dart_meta.dart" as meta',
    ]
    ..variables = [
      variable('non_jsonable_types')
      ..isPublic = false
      ..type = 'List<String>'
      ..init = '''[ 
  'String', 'int', 'double', 'bool', 'num',
  'Map', 'List', 'DateTime', 'dynamic',
]'''
    ]
    ..includeLogger = true
    ..parts = [
      part('dart_meta')
      ..variables = [
        variable('pub_type_re')
        ..type = 'RegExp'
        ..isPublic = false
        ..init = 'new RegExp(r"(git:|http:|[\./.])")'
      ]
      ..enums = [
        enum_('access')
        ..jsonSupport = true
        ..doc = 'Access for member variable - ia - inaccessible, ro - read/only, rw read/write'
        ..values = [
          id('ia'), id('ro'), id('rw')
        ],
        enum_('pub_dep_type')
        ..doc = 'Dependency type of a PubDependency '
        ..jsonSupport = true
        ..values = [
          id('path'), id('git'), id('hosted')
        ],
      ]
      ..classes = [
        class_('variable')
        ..members = [
          id_member('variable'),
          doc_member('variable'),
          parent_member('variable'),
          public_member('variable'),
          member('type')
          ..doc = 'Type for the variable'
          ..type = 'String',
          member('init')
          ..doc = '''
Data used to initialize the variable
If init is a String and type is not specified, [type] is a String

member('foo')..init = 'goo' => String foo = "goo";

If init is a String and type is specified, then:

member('foo')..type = 'int'..init = 3
  String foo = 3;
member('foo')..type = 'DateTime'..init = 'new DateTime(1929, 10, 29)' => 
  DateTime foo = new DateTime(1929, 10, 29);

If init is not specified, it will be inferred from init if possible:

member('foo')..init = 'goo'
  String foo = "goo";
member('foo')..init = 3
  String foo = 3;
member('foo')..init = [1,2,3]
  Map foo = [1,2,3];

'''
          ..type = 'dynamic',
          member('is_final')
          ..doc = 'True if the variable is final'
          ..type = 'bool'
          ..classInit = 'false',
          member('is_const')
          ..doc = 'True if the variable is const'
          ..type = 'bool'
          ..classInit = 'false',
          member('is_static')
          ..doc = 'True if the variable is static'
          ..type = 'bool'
          ..classInit = 'false',
          member('name')
          ..doc = "Name of the enum class generated sans access prefix"
          ..access = Access.RO,
          member('var_name')
          ..doc = 'Name of variable - varies depending on public/private'
          ..access = Access.RO,
        ],
        class_('enum')
        ..doc = '''Defines an enum - to be generated idiomatically as a class
See (http://stackoverflow.com/questions/13899928/does-dart-support-enumerations)
At some point when true enums are provided this may be revisited.
'''
        ..members = [
          id_member('enum'),
          doc_member('enum'),
          public_member('enum'),
          parent_member('enum'),
          member('values')
          ..doc = "List of id's naming the values"
          ..type = 'List<Id>'
          ..classInit = '[]',
          member('json_support')
          ..doc = "If true, generate toJson/fromJson on wrapper class"
          ..type = 'bool'
          ..classInit = 'false',
          member('has_rand_json')
          ..doc = "If true, generate randJson"
          ..type = 'bool'
          ..classInit = 'false',
          member('name')
          ..doc = "Name of the enum class generated sans access prefix"
          ..access = Access.RO,
          member('enum_name')
          ..doc = "Name of the enum class generated with access prefix"
          ..access = Access.RO,
          member('has_custom')
          ..doc = 'If true includes custom block for additional user supplied ctor code'
          ..type = 'bool'
          ..classInit = 'false',
          member('is_snake_string')
          ..doc = 'If true string value for each entry is snake case (default is shout)'
          ..type = 'bool'
          ..classInit = 'false',
        ],
        class_('pub_dependency')
        ..doc = 'A dependency of the system'
        ..members = [
          member('name')
          ..ctors = ['']
          ..doc = 'Name of dependency',
          member('version')
          ..doc = 'Required version for this dependency'
          ..classInit = 'any',
          member('path')
          ..doc = "Path to package, infers package type for git (git:...), hosted (http:...), path ",
          member('git_ref')
          ..doc = "Git reference",
          member('type')
          ..doc = "Type for the pub dependency"
          ..jsonTransient = true
          ..type = 'PubDepType'
          ..access = IA,
        ],
        class_('pub_spec')
        ..doc = 'Information for the pubspec of the system'
        ..members = [
          // In general id is final - but here we want json
          id_member('pub spec')..isFinal = false,
          doc_member('pub spec'),
          parent_member('pub spec'),
          member('version')
          ..doc = 'Version for this package'
          ..classInit = '0.0.1',
          member('name')
          ..doc = '''
Name of the project described in spec.
If not set, id of system is used.
''',
          member('author')
          ..doc = "Author of the pub package",
          member('homepage')
          ..doc = "Homepage of the pub package",
          member('dependencies')
          ..type = 'List<PubDependency>'
          ..classInit = '[]',
          member('dev_dependencies')
          ..type = 'List<PubDependency>'
          ..classInit = '[]',
        ],
        class_('system')
        ..doc = 'Defines a dart system (collection of libraries and apps)'
        ..members = [
          non_final_id_member('system'),
          doc_member('system'),
          member('root_path')
          ..doc = 'Path to which code is generated',
          member('scripts')
          ..doc = 'Scripts in the system'
          ..type = 'List<Script>'
          ..classInit = '[]',
          member('app')
          ..doc = 'App for this package'
          ..type = 'App',
          member('test_libraries')
          ..doc = 'List of test libraries of this app'
          ..type = 'List<Library>'
          ..classInit = '[]',
          member('libraries')
          ..doc = 'Libraries in the system'
          ..type = 'List<Library>'
          ..classInit = '[]',
          member('all_libraries')
          ..doc = 'Regular and test libraries'
          ..type = 'List<Library>'
          ..classInit = '[]',
          member('pub_spec')
          ..doc = 'Information for the pubspec'
          ..type = 'PubSpec',
          member('jsonable_classes')
          ..doc = 'Map of all classes that have jsonSupport'
          ..type = 'Map<String,Class>'
          ..classInit = '{}',
          member('finalized')
          ..doc = 'Set to true on finalize'
          ..access = Access.RO
          ..type = 'bool'
          ..classInit = 'false',
          member('generate_pub_spec')
          ..doc = 'If true generate a pubspec.xml file'
          ..type = 'bool'
          ..classInit = 'true',
          member('license')
          ..doc = '''
A string indicating the license.
A map of common licenses is looked up and if found a link
to that license is used. The current keys of the map are:
[ 'boost', 'mit', 'apache-2.0', 'bsd-2', 'bsd-3', 'mozilla-2.0' ]
Otherwise the text is assumed to be the
text to include in the license file.
''',
          member('include_readme')
          ..doc = 'If true standard outline for readme provided'
          ..type = 'bool'
          ..classInit = 'false',
          member('introduction')
          ..doc = 'A brief introduction for this system, included in README.md',
          member('purpose')
          ..doc = 'Purpose for this system, included in README.md',
          member('todos')
          ..doc = 'List of todos included in the readme - If any present includeReadme assumed true'
          ..type = 'List<String>'
          ..classInit = '[]',
          member('include_hop')
          ..doc = 'If true generates tool folder with hop_runner'
          ..type = 'bool'
          ..classInit = 'false',
        ],
        class_('test')
        ..doc = 'A test generated in a standard format',
        class_('script_arg')
        ..doc = 'An agrument to a script'
        ..members = [
          id_member('script argument'),
          doc_member('script argument'),
          parent_member('script argument'),
          member('name')
          ..doc = 'Name of the the arg (emacs naming convention)'
          ..access = Access.RO,
          member('is_required')
          ..doc = 'If true the argument is required'
          ..type = 'bool'
          ..classInit = 'false',
          member('is_flag')
          ..doc = 'If true this argument is a boolean flag (i.e. no option is required)'
          ..type = 'bool'
          ..classInit = 'false',
          member('is_multiple')
          ..doc = 'If true the argument may be specified mutiple times'
          ..type = 'bool'
          ..classInit = 'false',
          member('defaults_to')
          ..doc = 'Used to initialize the value in case not set'
          ..type = 'dynamic',
          member('allowed')
          ..doc = 'A list of allowed values to choose from'
          ..type = 'List<String>'
          ..classInit = '[]',
          member('position')
          ..doc = 'If not null - holds the position of a positional (i.e. unnamed) argument'
          ..type = 'int',
          member('abbr')
          ..doc = 'An abbreviation (single character)'
        ],
        class_('script')
        ..doc = 'A typical script - (i.e. like a bash/python/ruby script but in dart)'
        ..members = [
          id_member('script'),
          doc_member('script'),
          parent_member('script'),
          custom_member('script'),
          member('imports')
          ..doc = 'List of imports to be included by this script'
          ..type = 'List<String>'
          ..classInit = '[]',
          member('args')
          ..doc = 'Arguments for this script'
          ..type = 'List<ScriptArg>'
          ..classInit = '[]',
        ],
        class_('app')
        ..doc = 'Defines a dart *web* application. For non-web console app, use Script'
        ..members = [
          id_member('app'),
          doc_member('app'),
          parent_member('app'),
          custom_member('app'),
          member('classes')
          ..doc = 'Classes defined in this app'
          ..type = 'List<Class>'
          ..classInit = '[]',
          member('libraries')
          ..doc = 'List of libraries of this app'
          ..type = 'List<Library>'
          ..classInit = '[]',
          member('variables')
          ..doc = 'List of global variables for this library'
          ..type = 'List<Variable>'
          ..classInit = '[]',
          member('is_web_ui')
          ..doc = 'If true this is a web ui app'
          ..type = 'bool'
          ..classInit = 'false',
        ],
        class_('library')
        ..doc = "Defines a dart library - a collection of parts"
        ..members = [
          id_member('library'),
          doc_member('library'),
          parent_member('library'),
          custom_member('library'),
          member('imports')
          ..doc = 'List of imports to be included by this library'
          ..type = 'List<String>'
          ..classInit = '[]',
          member('parts')
          ..doc = 'List of parts in this library'
          ..type = 'List<Part>'
          ..classInit = '[]',
          member('variables')
          ..doc = 'List of global variables for this library'
          ..type = 'List<Variable>'
          ..classInit = '[]',
          member('classes')
          ..doc = 'Classes defined in this library'
          ..type = 'List<Class>'
          ..classInit = '[]',
          member('enums')
          ..doc = 'Enums defined in this library'
          ..type = 'List<Enum>'
          ..classInit = '[]',
          member('name')
          ..doc = "Name of the library - for use in naming the library file, the 'library' and 'part of' statements"
          ..access = Access.RO,
          member('include_logger')
          ..doc = 'If true includes logging support and a _logger'
          ..type = 'bool'
          ..classInit = 'false',
          member('is_test')
          ..doc = 'If true this library is a test library to appear in test folder'
          ..type = 'bool'
          ..classInit = 'false',
          member('include_main')
          ..doc = 'If true a main is included in the library file'
          ..type = 'bool'
          ..classInit = 'false',
          member('path')
          ..doc = 'Set desired if generating just a lib and not a package',
          member('lib_main')
          ..doc = 'If set the main function'
        ],
        class_('part')
        ..doc = "Defines a dart part - as in 'part of' source file"
        ..members = [
          id_member('part'),
          doc_member('part'),
          parent_member('part'),
          custom_member('app'),
          member('classes')
          ..doc = 'Classes defined in this part of the library'
          ..type = 'List<Class>'
          ..classInit = '[]',
          member('enums')
          ..doc = 'Enums defined in this part of the library'
          ..type = 'List<Enum>'
          ..classInit = '[]',
          member('name')
          ..doc = "Name of the part - for use in naming the part file"
          ..access = Access.RO,
          member('file_path')
          ..doc = "Path to the generated part dart file"
          ..access = Access.RO,
          member('variables')
          ..doc = 'List of global variables in this part'
          ..type = 'List<Variable>'
          ..classInit = '[]',
        ],
        class_('class')
        ..doc = 'Metadata associated with a Dart class'
        ..members = [
          id_member('Dart class'),
          doc_member('Dart class'),
          parent_member('Dart class'),
          public_member('Dart class'),
          member('mixins')
          ..doc = 'List of mixins'
          ..type = 'List<String>'
          ..classInit = '[]',
          member('extend')
          ..doc = 'Any extends (NOTE extend not extends) declaration for the class - conflicts with mixin'
          ..type = 'String',
          member('implement')
          ..doc = 'Any implements (NOTE implement not implements)'
          ..type = 'List<String>'
          ..classInit = '[]',
          custom_member('Dart class'),
          member('default_member_access')
          ..doc = 'Default access for members'
          ..classInit = 'Access.RW'
          ..type = 'Access',
          member('members')
          ..doc = 'List of members of this class'
          ..type = 'List<Member>'
          ..classInit = '[]',
          member('ctor_customs')
          ..doc = 'List of ctors requiring custom block'
          ..type = 'List<String>'
          ..classInit = '[]',
          member('ctor_const')
          ..doc = 'List of ctors that should be const'
          ..type = 'List<String>'
          ..classInit = '[]',
          member('ctors')
          ..doc = 'List of ctors of this class'
          ..type = 'Map<String,Ctor>'
          ..classInit = '{}'
          ..access = Access.RO,
          member('is_abstract')
          ..doc = "If true, class is abstract"
          ..type = 'bool'
          ..classInit = 'false',
          member('json_support')
          ..doc = "If true, generate toJson/fromJson on all members that are not jsonTransient"
          ..type = 'bool'
          ..classInit = 'false',
          member('has_rand_json')
          ..doc = "If true, generate randJson function"
          ..type = 'bool'
          ..classInit = 'false',
          member('ctor_sans_new')
          ..doc = "If true creates library functions to construct forwarding to ctors"
          ..type = 'bool'
          ..classInit = 'false',
          member('name')
          ..doc = "Name of the class - sans any access prefix (i.e. no '_')"
          ..access = Access.RO,
          member('class_name')
          ..doc = "Name of the class, including access prefix"
          ..access = Access.RO,
        ],
        class_('ctor')
        ..doc = 'Metadata associated with a constructor'
        ..members = [
          member('class_name')
          ..doc = "Name of the class of this ctor.",
          member('name')
          ..doc = "Name of the ctor. If 'default' generated as name of class, otherwise as CLASS.NAME()",
          member('members')
          ..doc = 'List of members initialized in this ctor'
          ..type = 'List<Member>'
          ..classInit = '[]',
          member('opt_members')
          ..doc = 'List of optional members initialized in this ctor (i.e. those in [])'
          ..type = 'List<Member>'
          ..classInit = '[]',
          member('named_members')
          ..doc = 'List of optional members initialized in this ctor (i.e. those in {})'
          ..type = 'List<Member>'
          ..classInit = '[]',
          member('has_custom')
          ..doc = 'If true includes custom block for additional user supplied ctor code'
          ..type = 'bool'
          ..classInit = 'false',
          member('is_const')
          ..doc = 'True if the variable is const'
          ..type = 'bool'
          ..classInit = 'false',
        ],
        class_('member')
        ..doc = 'Metadata associated with a member of a Dart class'
        ..members = [
          id_member('class member'),
          doc_member('class member'),
          parent_member('class member'),
          member('type')
          ..doc = 'Type of the member'
          ..type = 'String'
          ..classInit = 'String',
          member('access')
          ..doc = 'Access level supported for this member'
          ..type = 'Access',
          member('class_init')
          ..type = 'dynamic'
          ..doc = '''
If provided the member will be initialized with value.
The type of the member can be inferred from the type
of this value.  Member type is defaulted to String. If
the type of classInit is a String and type of the
member is String, the text will be quoted if it is not
already. If the type of classInit is other than string
and the type of member is String (which is default)
the type of member will be set to
classInit.runtimeType.

''',
          member('ctor_init')
          ..doc = '''
If provided the member will be initialized to this
text in generated ctor initializers''',
          member('ctors')
          ..doc = "List of ctor names to include this member in"
          ..type = 'List<String>'
          ..classInit = '[]',
          member('ctors_opt')
          ..doc = "List of ctor names to include this member in as optional parameter"
          ..type = 'List<String>'
          ..classInit = '[]',
          member('ctors_named')
          ..doc = "List of ctor names to include this member in as named optional parameter"
          ..type = 'List<String>'
          ..classInit = '[]',
          member('is_final')
          ..doc = 'True if the member is final'
          ..type = 'bool'
          ..classInit = 'false',
          member('is_const')
          ..doc = 'True if the member is const'
          ..type = 'bool'
          ..classInit = 'false',
          member('is_static')
          ..doc = 'True if the member is static'
          ..type = 'bool'
          ..classInit = 'false',
          member('json_transient')
          ..doc = 'True if the member should not be serialized if the parent class has jsonSupport'
          ..type = 'bool'
          ..classInit = 'false',
          member('name')
          ..doc = "Name of variable for the member, excluding access prefix (i.e. no '_')"
          ..access = Access.RO,
          member('var_name')
          ..doc = 'Name of variable for the member - varies depending on public/private'
          ..access = Access.RO,
        ]
      ]
    ];

  System ebisu = system('ebisu')
    ..includeReadme = true
    ..includeHop = true
    ..introduction = 'A library supporting code generation of Dart pub packages and many constituent assets.'
    ..purpose = '''
There are two potentially distinct purposes for this package. First, for those
wanting to keep consistency across Dart assets being developed, a declarative
approach to the specification of them as well as their subsequent generation is
provided for. This is soothing to people with extreme need for consistency and
can be helpful for those wanting strict structure for projects expected to grow
large.

A second purpose is for large scale data driven development efforts that are
highly structured/standardized. This library can be used to bootstrap their
development. 

Example:

- Model driven development. For example, suppose _Json Schema_ were used to
  define data models. This library could be used as a base to generate GUI
  supporting code.


## How It Works

This library does not attempt to allow for the generation of all aspects of Dart
code. Rather the focus is on generation of the structure of items along with
user ability to augment. These items or *code assets* include, but are not
limited to:

- Libraries
- Parts
- Scripts
- Classes
- Enumerations
- Members
- Variables

The idea is come up with a reasonable/good enough single approach that works in
defining the assets. Then provide enough flexibility to allow developers to do
what is needed (i.e. not be too restrictive). As more common patterns develop
support for them may be added. The hope is the benefit of consistency will
outweigh the need for creativity along the dimensions chosen for
generation. Ideally there will be little loss on the creativity front since the
concepts generated are pretty standardized already (e.g. location of library
files, where parts go and how they are laied out, where pubspec goes and its
contents, the layout of a class, ...etc)

For a small taste:

        class_('schema_node')
        ..doc = 'Represents one node in the schema diagram'
        ..members = [
          member('schema')
          ..doc = 'Referenced schema this node portrays'
          ..type = 'Schema',
          member('links')
          ..doc = 'List of links (resulting in graph edge) from this node to another'
          ..type = 'List<String>'
        ]

That declaration snippet will define a class called _SchemNode_ with two members
_schema_ of type _Schema_ and _links_ of type _List_. The _doc_ attribute is a
common way of providing descriptions for { _classes_, _members_, _variables_,
_pubSpec_ } and appear as document comments.

There are areas where the code generation gets a bit opinionated. For example,
members are either public or private and the naming convention is enforced - so
you do not need to name variables with an underscore prefix; that will be taken
care of. By default members are public, so to make them private just set
_isPublic = false_. But then, what about accessors. These are very boilerplate,
so the approach taken is to add a designation called _access_ for each member
which is one of:

- ReadWrite (_AccessType.RW_): In this case the field is public and no accessors
  are provided

- ReadOnly (_AccessType.RO_): In this case the field is private and the typical
  _get_ accessor is provided

- Inaccessible (_Accessor.IA_): In this case the field is private and no
  accessors are provided

The default access is _ReadWrite_.

### A Note on Naming

All assets are named, because they all end up in code with some form of file or
identifier associated with them. All identifer names are provided to
declarations in _snake\\_case_ form. This is a hard rule, as the code generation
chooses the appropriate casing in the generated assets based on context. For
instance, the name _schema\\_node_ is a class and therefore will be generated as
_SchemaNode_. Similarly, _schema\\_node_ as a variable name would be generated
as _schemaNode_.

### Customization

Since the shell/structure is what is generated, there needs to be a way to add
user supplied code and have it mixin with what is generated. This is
accomplished with code protection blocks. Pretty much all *text* that appears
between blocks are protected.

    // custom <TAG>
       ... Custom text here ...
    // end <TAG>

All other code will be rewritten on code generation. Keep in mind that the
protection blocks are predefined in the libraries and templates, so the user
never attempts to create a custom block directly in generated code.

### Regeneration

When code is regenerated, this library creates the text to be written to the
file and matches up all protection blocks with those existing in the target file
on disk. It first does the merge of generated and custom text in memory and then
compares that to the full contents on disk. If there is no change in the
contents of the file, a message like the following will be output:
    
    No change: .../library/foo.dart

If the regeneration results in a change, due to new *code assets* having been
added to the definition or less frequently due to changes in the ebisu
library/templates, a message like the following will be output:

    Wrote: .../library/foo.dart

'''
    ..testLibraries = [
      library('setup')
      ..imports = [
        'package:ebisu/ebisu_dart_meta.dart', 
        'package:path/path.dart',
        'io',
        'utils.dart',
      ]
      ..variables = [
        variable('scratch_remove_me_folder')
        ..isPublic = false
      ]
      ..includeMain = false
      ..includeLogger = true,
      library('test_code_generation')
      ..imports = [
        'package:ebisu/ebisu_dart_meta.dart', 
        'setup.dart', 
        'utils.dart',
        'package:path/path.dart', 
        'package:yaml/yaml.dart', 
        'io', 
        'async', ]
      ..includeLogger = true,
      library('expect_basic_class')
      ..imports = [ 'scratch_remove_me/lib/basic_class.dart' ],
      library('expect_various_ctors')
      ..imports = [ 'scratch_remove_me/lib/various_ctors.dart' ],
      library('expect_multi_parts')
      ..imports = [ 'scratch_remove_me/lib/two_parts.dart' ],
    ]
    ..todos = [
      'Add examples'
    ]
    ..license = 'boost'
    ..rootPath = _topDir
    ..pubSpec = (pubspec('ebisu')
        ..doc = '''
A library that supports code generation of the structure Dart (and potentially
other languages like D) using a fairly declarative aproach.
'''
        ..homepage = 'https://github.com/patefacio/ebisu'
        ..dependencies = [
          pubdep('path'),
          pubdep('id'),
        ]
        ..devDependencies = [
          pubdep('unittest'),
          pubdep('yaml'),
        ]
                 )
    ..libraries = [
      library('ebisu')
      ..doc = 'Primary library for client usage of ebisu'
      ..includeLogger = true
      ..variables = [
        variable('ebisu_path')
        ..doc = 'Path to this package - for use until this becomes a pub package'
        ..isFinal = true
        ..init = "Platform.environment['EBISU_PATH']",
        variable('ebisu_author')
        ..doc = 'Author of the generated code'
        ..isFinal = true
        ..init = "Platform.environment['EBISU_AUTHOR']",
        variable('ebisu_homepage')
        ..doc = 'Hompage for pubspec'
        ..isFinal = true
        ..init = "Platform.environment['EBISU_HOMEPAGE']",
        variable('ebisu_pub_versions')
        ..doc = '''
File containing default pub versions. Dart code generation at times
generates code that requires packages. For example, generated
test cases require unittest, generated code can require logging,
hop support requries hop. Since the pubspec yaml is generated
the idea here is to pull the versions of these packages out of 
the code and into a config file. Then to upgrade multiple packages
with multiple pubspecs would entail updating the config file and
regenerating.
'''
        ..isFinal = true
        ..init = '''
(Platform.environment['EBISU_PUB_VERSIONS'] != null) ?
  Platform.environment['EBISU_PUB_VERSIONS'] :
  "\${Platform.environment['HOME']}/.ebisu_pub_versions.json"''',
        variable('license_map')
        ..type = 'Map<String,String>'
        ..init = '''
{

  'boost' : 'License: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>',
  'mit' : 'License: <a href="http://opensource.org/licenses/MIT">MIT License</a>',
  'apache-2.0' : 'License: <a href="http://opensource.org/licenses/Apache-2.0">Apache License 2.0</a>',
  'bsd-3' : 'License: <a href="http://opensource.org/licenses/BSD-3-Clause">BSD 3-Clause "Revised"</a>',
  'bsd-2' : 'License: <a href="http://opensource.org/licenses/BSD-2-Clause">BSD 2-Clause</a>',
  'mozilla-2.0' : 'License: <a href="http://opensource.org/licenses/MPL-2.0">Mozilla Public License 2.0 </a>',

}'''

      ]
      ..imports = [
        'io',
        '"package:path/path.dart" as path'
      ]
      ..parts = [
        part('ebisu')
        ..classes = [
          class_('context')
          ..doc = "Convenience wrapper for a map - passed into templates as variable '_'"
          ..members = [
            member('data')
            ..ctors = ['']
            ..isFinal = true
            ..doc = "Data being wrapped"
            ..type = 'Map'
            ..access = Access.RO
          ]
        ]
      ],
      ebisu_compiler,
      ebisu_dart_meta,
      ebisu_utils,
    ];

  /*
  ebisu_dart_meta.parts.forEach((part) {
    part.classes.forEach((c) {
      c.jsonSupport = true;
    });
  });
  */

  ebisu.generate();
}