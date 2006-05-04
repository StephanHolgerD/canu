use strict;

#  Create the post-unitigger consensus jobs.

sub createPostUnitiggerConsensusJobs {
    my $pstats            = getGlobal("processStats");

    system("mkdir $wrk/5-consensus") if (! -d "$wrk/5-consensus");

    return if (-e "$wrk/5-consensus/jobsCreated.success");

    if (! -e "$wrk/5-consensus/$asm.partFile") {

        #  Then, build a partition information file, and do the partitioning.
        #
        open(F, "ls $wrk/4-unitigger/*.cgb |") or die;
        while (<F>) {
            chomp;

            if (m/^.*(\d\d\d).cgb$/) {
                if (runCommand("grep mid: $_ | sed 's/mid:/$1 /' >> $wrk/5-consensus/$asm.partFile")) {
                    print STDERR "Failed to grep mid: from CGB output in $_.\n";
                    exit(1);
                }
            } else {
                print STDERR "WARNING: didn't match $_ for CGB filename!\n";
            }
        }
        close(F);

        my $cmd;
        $cmd  = "$bin/partitionFragStore ";
        $cmd .= "$wrk/5-consensus/$asm.partFile ";
        $cmd .= "$wrk/$asm.frgStore ";
        $cmd .= "$wrk/$asm.frgStore_cns1part ";
        $cmd .= "> $wrk/5-consensus/partitionfragstore.err 2>&1";
        if (runCommand($cmd)) {
            print STDERR "Failed to partition the fragStore.\n";
            rename "$wrk/5-consensus/$asm.partFile", "$wrk/5-consensus/$asm.partFile.FAILED";
            exit(1);
        }
    }

    ########################################
    #
    #  Build consensus jobs for the grid -- this is very similar to that in createConsensusJobs.pl
    #
    #  Create a set of shell scripts to run consensus, one per cgb
    #  batch.  The last batch is not used, the small tests BPW has
    #  tried always as an empty file there.
    #
    my $jobP;
    my $jobs = 0;

    open(CGB, "ls $wrk/4-unitigger/*.cgb |") or die;
    while (<CGB>) {
        if (m/^.*(\d\d\d).cgb/) {
            $jobP .= "$1\t";
            $jobs++;
        } else {
            print STDERR "WARNING: didn't match $_ for CGB filename!\n";
        }
    }
    close(CGB);

    $jobP = join ' ', sort { $a <=> $b } split '\s+', $jobP;

    open(F, "> $wrk/5-consensus/consensus.sh") or die "Can't open '$wrk/5-consensus/consensus.sh'\n";
    print F "#!/bin/sh\n";
    print F "\n";
    print F "jobid=\$SGE_TASK_ID\n";
    print F "if [ x\$jobid = x -o x\$jobid = xundefined ]; then\n";
    print F "  jobid=\$1\n";
    print F "fi\n";
    print F "if [ x\$jobid = x ]; then\n";
    print F "  echo Error: I need SGE_TASK_ID set, or a job index on the command line.\n";
    print F "  exit 1\n";
    print F "fi\n";
    print F "jobp=`echo $jobP | cut -d' ' -f \$jobid`\n";
    print F "\n";
    print F "if [ -e $wrk/5-consensus/${asm}_\$jobp.success ] ; then\n";
    print F "  exit 0\n";
    print F "fi\n";
    print F "\n";
    print F "echo \\\n";
    print F "$gin/consensus \\\n";
    print F "  -P -m -U -z \\\n";
    print F "  -S \$jobp \\\n";
    print F "  -o $wrk/5-consensus/${asm}_\$jobp.cgi \\\n";
    print F "  $wrk/$asm.frgStore_cns1part \\\n";
    print F "  $wrk/4-unitigger/${asm}_\$jobp.cgb \\\n";
    print F " \\> $wrk/5-consensus/${asm}_\$jobp.err 2\\>\\&1\n";
    print F "\n";
    print F "$pstats \\\n" if (defined($pstats));
    print F "$gin/consensus \\\n";
    print F "  -P -m -U -z \\\n";
    print F "  -S \$jobp \\\n";
    print F "  -o $wrk/5-consensus/${asm}_\$jobp.cgi \\\n";
    print F "  $wrk/$asm.frgStore_cns1part \\\n";
    print F "  $wrk/4-unitigger/${asm}_\$jobp.cgb \\\n";
    print F " > $wrk/5-consensus/${asm}_\$jobp.err 2>&1 \\\n";
    print F "&& \\\n";
    print F "touch $wrk/5-consensus/${asm}_\$jobp.success\n";
    close(F);

    chmod 0755, "$wrk/5-consensus/consensus.sh";

    if (getGlobal("useGrid") && getGlobal("cnsOnGrid")) {
        my $cmd;
        $cmd  = "qsub -p 0 -r y -N cns1_${asm} ";
        $cmd .= "-t 1-$jobs ";
        $cmd .= "-j y -o /dev/null ";
        $cmd .= "$wrk/5-consensus/consensus.sh\n";
        pleaseExecute($cmd);
        touch("$wrk/5-consensus/jobsCreated.success");
        exit(0);
    } else {
        for (my $i=1; $i<=$jobs; $i++) {
            &scheduler::schedulerSubmit("sh $wrk/5-consensus/consensus.sh $i");
        }

        &scheduler::schedulerSetNumberOfProcesses(getGlobal("cnsConcurrency"));
        &scheduler::schedulerFinish();

        touch("$wrk/5-consensus/jobsCreated.success");
    }
}

1;
