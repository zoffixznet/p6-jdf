use v6;
use XML;

role Jdf::Pool {
    has XML::Element $.Pool;

    method new(XML::Element $Pool) {
        return self.bless(:$Pool);
    }
}

class Jdf::AuditPool is Jdf::Pool {
    method Created {
        my $c = Jdf::get($.Pool, "Created");
        return {
            AgentName => $c<AgentName>,
            AgentVersion => $c<AgentVersion>,
            TimeStamp => DateTime.new($c<TimeStamp>)
        };
    }
}

class Jdf::ResourcePool is Jdf::Pool {
    method ColorantOrder {
        my $co = Jdf::get($.Pool, <ColorantOrder>, Recurse => 1);
        my @ss = Jdf::get($co, <SeparationSpec>, Single => False);
        return @ss.map(*<Name>);
    }

    method Layout {
        my $layout = Jdf::get($.Pool, <Layout>);
        my @pa = $layout<SSi:JobPageAdjustments>.split(' ');
        my @sigs = Jdf::get($layout, <Signature>, Single => False);
        return {
            Bleed => Jdf::mm($layout<SSi:JobDefaultBleedMargin>),
            PageAdjustments => {
                Odd => { X => Jdf::mm(@pa[0]), Y => Jdf::mm(@pa[1]) },
                Even => { X => Jdf::mm(@pa[2]), Y => Jdf::mm(@pa[3]) }
            },
            Signatures => parseSignatures(@sigs),
        };
    }

    method Runlist {
        my $runlist = Jdf::get($.Pool, <RunList>);
        my @runlists = Jdf::get($runlist, <RunList>, Single => False);
        my @files;
        for @runlists -> $root {
            my $layout = Jdf::get($root, <LayoutElement>);
            my $pagecell = Jdf::get($root, <SSi:PageCell>);
            my $filespec = Jdf::get($layout, <FileSpec>);
            @files.push: {
                Run => $root<Run>,
                Page => $root<Run> + 1,
                Url => IO::Path.new($filespec<URL>),
                CenterOffset => parseOffset($pagecell<SSi:RunListCenterOffset>),
                Centered =>
                    $pagecell<SSi:RunListCentered> == 0 ?? False !! True,
                Offsets => parseOffset($pagecell<SSi:RunListOffsets>),
                Scaling => parseScaling($pagecell<SSi:RunListScaling>)
            };
        }
        return @files;
    }

    sub parseSignatures(@signatures) {
        my @s;
        for @signatures {
            my %sig =
                Name => $_<Name>,
                PressRun => $_<SSi:PressRunNo>.Int
            ;
            @s.push: {%sig};
        }
        return @s;
    }

    our sub parseOffset($offset) {
        my @sets = $offset.split(' ');
        @sets = (0, 0) if $offset eq "0";
        return { X => Jdf::mm(@sets[0]), Y => Jdf::mm(@sets[1]) };
    }

    our sub parseScaling($scaling) {
        my @sc = $scaling.split(' ');
        return { X => @sc[0]*100, Y => @sc[1]*100 };
    }
}

class Jdf {
    has XML::Document $.jdf;
    has Jdf::AuditPool $.AuditPool;
    has Jdf::ResourcePool $.ResourcePool;

    method new(Str $jdf-xml) returns Jdf {
        my XML::Document $jdf = from-xml($jdf-xml);
        my Jdf::AuditPool $AuditPool .= new(getPool($jdf, "AuditPool"));
        my Jdf::ResourcePool $ResourcePool .= new(getPool($jdf, "ResourcePool"));
        return self.bless(:$jdf, :$AuditPool, :$ResourcePool);
    }

    our sub get(XML::Element $xml, Str $TAG, Bool :$Single = True,Int :$Recurse = 0) {
        return $xml.elements(:$TAG, SINGLE => $Single, RECURSE => $Recurse);
    }

    sub getPool(XML::Document $xml, Str $name) {
        return $xml.elements(TAG => $name, :SINGLE);
    }

    our proto mm($pts) { * }

    our multi sub mm(Str $pts) {
        mm($pts.Rat);
    }

    our multi sub mm(Int $pts) {
        mm($pts.Rat);
    }

    our multi sub mm(Rat $pts) {
        my Rat constant $inch = 25.4;
        my Rat constant $mm = $inch / 72;
        return ($mm * $pts).round;
    }
}

# vim: ft=perl6 ts=4
