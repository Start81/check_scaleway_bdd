#!/usr/bin/perl -w
#=============================================================================== 
# Script Name   : check_scaleway_bdd.pl
# Usage Syntax  : check_scaleway_bdd.pl -T <Token> -r <Scaleway region>  -N <BDD name> | -i <id> [-m <Metric_Name>] | -L | -b -d <dbname> ] [-w <threshold> -c <threshold> ]
# Version       : 1.1.2
# Last Modified : 21/09/2023
# Modified By   : Start81
# Description   : This is a Nagios check that uses Scaleway s REST API to get bdd metrics and status
# Depends On    :  Monitoring::Plugin Data::Dumper JSON REST::Client Readonly File::Basename DateTime 
# 
# Changelog: 
#    Legend: 
#       [*] Informational, [!] Bugfix, [+] Added, [-] Removed 
#  - 11/04/2023| 1.0.0 | [*] First release
#  - 13/06/2023| 1.0.1 | [*] Rework output
#  - 21/06/2023| 1.0.2 | [*] check if instance state is in %state hastable
#  - 28/06/2023| 1.1.0 | [+] Add backup check and add cluster support 
#  - 30/06/2023| 1.1.1 | [!] bug fix => no unit in perfdata for total_connections
#  - 21/09/2023| 1.1.2 | [*] clean-up code
#===============================================================================

use strict;
use warnings;
use Monitoring::Plugin;
use Data::Dumper;
use REST::Client;
use JSON;
use utf8; 
use Readonly;
use File::Basename;
use DateTime;
Readonly our $VERSION => "1.1.2";
my %state  =("ready"=>0, 
"provisioning"=>0,
"configuring"=>0, 
"deleting"=>2, 
"error"=>2, 
"autohealing"=>0, 
"locked"=>2, 
"initializing"=>0, 
"disk_full"=>2, 
"backuping"=>0, 
"snapshotting"=>0,
"restarting"=>0);
my %backup_state =("unknown" => 2,
"creating" => 0,
"ready" => 0,
"restoring" => 0,
"deleting" => 0,
"error" => 2,
"exporting" => 0,
"locked" => 2);
my %metrics = ('cpu_usage_percent' => '%',
    'mem_usage_percent' => '%',
    'total_connections' => '',
    'disk_usage_percent' => '%',
    'total_connections_percent' => '%',
    'backup_age' => 'h'
);
my $me = basename($0);
my $o_verb;
sub verb { my $t=shift; print $t,"\n" if ($o_verb) ; return 0}
my $np = Monitoring::Plugin->new(
    usage => "Usage: %s  -T <Token> -r <Scaleway region>  -N <BDD name> | -i <id> [-m <Metric_Name>] | -L  | -b -d <dbname> ] [-w <threshold> -c <threshold> ]\n",
    plugin => $me,
    shortname => " ",
    blurb => "$me is a Nagios check that use Scaleway s REST API to get bdd metrics and status ",
    version => $VERSION,
    timeout => 30
);
$np->add_arg(
    spec => 'Token|T=s',
    help => "-T, --Token=STRING\n"
          . ' Token for api authentication',
    required => 1
);
$np->add_arg(
    spec => 'name|N=s',
    help => "-N, --name=STRING\n"
          . '   instance name',
    required => 0
);
$np->add_arg(
    spec => 'id|i=s',
    help => "-i, --id=STRING\n"
          . '   instance id',
    required => 0
);
$np->add_arg(
    spec => 'apiversion|a=s',
    help => "-a, --apiversion=string\n"
          . '  Scaleway API version',
    required => 1,
    default => 'v1'
);
$np->add_arg(
    spec => 'warning|w=s',
    help => "-w, --warning=threshold\n" 
          . '   See https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT for the threshold format.',
);
$np->add_arg(
    spec => 'critical|c=s',
    help => "-c, --critical=threshold\n"  
          . '   See https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT for the threshold format.',
);
$np->add_arg(
    spec => 'listInstance|L',
    help => "-L, --listInstance\n"  
          . '   Autodiscover instance',

);
$np->add_arg(
    spec => 'region|r=s',
    help => "-r, --region=STRING\n"
          . '  Scaleway region',
    required => 1
);
$np->add_arg(
    spec => 'metric|m=s',
    help => "-m, --metric=STRING\n"
          . '  bdd metrics : disk_usage_percent | total_connections | mem_usage_percent | cpu_usage_percent | total_connections_percent  ',
    required => 0
);
$np->add_arg(
    spec => 'backup|b',
    help => "-b, --backup\n"
          . '  check backup status and age',
    required => 0
);
$np->add_arg(
    spec => 'dbname|d=s',
    help => "-d, --dbname=STRING\n"
          . '  db name for backup check',
    required => 0
);
my @criticals = ();
my @warnings = ();
my @ok = ();
$np->getopts;
my $o_token = $np->opts->Token;
my $o_apiversion = $np->opts->apiversion;
my $o_list_instances = $np->opts->listInstance;
my $o_id = $np->opts->id;
$o_verb = $np->opts->verbose;
my $o_warning = $np->opts->warning;
my $o_critical = $np->opts->critical;
my $o_reg = $np->opts->region;
my $o_timeout = $np->opts->timeout;
my $o_metric = $np->opts->metric;
my $o_name = $np->opts->name;
my $o_backup = $np->opts->backup;
my $o_dbname = $np->opts->dbname;
#Check parameters
if ($o_backup){
    if (!$o_dbname){
        $np->plugin_die("database name missing");
    }
}
if ((!$o_list_instances) && (!$o_name) && (!$o_id)) {
    $np->plugin_die("instance name or id missing");
}
if (!$o_reg)
{
    $np->plugin_die("region missing");
}
if ($o_timeout > 60){
    $np->plugin_die("Invalid time-out");
}

#Rest client Init
my $client = REST::Client->new();
$client->setTimeout($o_timeout);
my $url ;
#Header
$client->addHeader('Content-Type', 'application/json;charset=utf8');
$client->addHeader('Accept', 'application/json');
$client->addHeader('Accept-Encoding',"gzip, deflate, br");
#Add authentication
$client->addHeader('X-Auth-Token',$o_token);
my $id; #id instances
my $i; 
my $max_connexions = 0;
my $msg = "";

if ((!$o_id)){
    #https://api.scaleway.com/rdb/v1/regions/fr-par/instances
    $url = "https://api.scaleway.com/rdb/$o_apiversion/regions/$o_reg/instances";
    my %instances;
    my $instance;
    verb($url);
    $client->GET($url);
    if($client->responseCode() ne '200'){
        $np->plugin_exit('UNKNOWN', " response code : " . $client->responseCode() . " Message : Error when getting instance list". $client->{_res}->decoded_content );
    }
    my $rep = $client->{_res}->decoded_content;
    my $instances_list_json = from_json($rep);
    verb(Dumper($instances_list_json));
    my $total_instance_count = $instances_list_json->{'total_count'};
    verb("Total instances count : $total_instance_count\n");
    $i = 0;
    while (exists ($instances_list_json->{'instances'}->[$i])){
        $instance = q{};
        $id = q{};
        $instance = $instances_list_json->{'instances'}->[$i]->{'name'};
        $id = $instances_list_json->{'instances'}->[$i]->{'id'}; 
        $instances{$instance}=$id;
        $i++;
    }
    my @keys = keys %instances;
    my $size;
    $size = @keys;
    verb ("hash size : $size\n");
    if (!$o_list_instances){
        #If instance name not found
        if (!defined($instances{$o_name})) {
            my $list="";
            my $key ="";
            #format a instance list
            $list = join(', ', @keys );
            $np->plugin_exit('UNKNOWN',"instance $o_name not found the instances list is $list"  );
        }
    } else {
        #Format autodiscover Xml for centreon
        my $xml='<?xml version="1.0" encoding="utf-8"?><data>'."\n";
        foreach my $key (@keys) {
            $xml = $xml . '<label name="' . $key . '"id="'. $instances{$key} . '"/>' . "\n"; 
        }
        $xml = $xml . "</data>\n";
        print $xml;
        exit 0;
    }
    # inject id in api url
    verb ("Found id : $instances{$o_name}\n");
    $id = $instances{$o_name};
};

$id = $o_id if (!$id);
verb ("id = $id\n") if (!$id);
if ($o_backup){
    
    my $rep_backup;
    my $backup_url="https://api.scaleway.com/rdb/$o_apiversion/regions/$o_reg/backups?order_by=created_at_desc&instance_id=$id&database_name=$o_dbname";
        verb($backup_url);
        $client->GET($backup_url);
        if($client->responseCode() ne '200'){
            $np->plugin_exit(UNKNOWN, " response code : " . $client->responseCode() . " Message : Error when getting backup list". $client->{_res}->decoded_content );
        }
        $rep_backup = $client->{_res}->decoded_content;
        my $backup_json = from_json($rep_backup);
        verb(Dumper($backup_json));
        if (!defined($backup_json->{'database_backups'}->[0])) {
            $np->plugin_exit('CRITICAL'," No Backup found with instance id $id and database_name $o_dbname");
        }
        my $backup = $backup_json->{'database_backups'}->[0];
        my $status = $backup_json->{'database_backups'}->[0]->{'status'};
        $msg ="backup instance_id = $id database_name $o_dbname status : $status";  
        if (!exists $state{$status} ){
            push( @criticals,"backup State $status is UNKNOWN "); 
        } else {
            push( @criticals,$msg) if ($state{$status}== 2);
        }
        my $dt_now = DateTime->now;
        my $backup_date = $backup_json->{'database_backups'}->[0]->{'created_at'};
        verb('backupTime ' . $backup_date);
        my @temp = split('T', $backup_date);
        $backup_date = $temp[0];
        my $backup_time = $temp[1];
        @temp = split('-', $backup_date);
        my @temp_time = split(':', $backup_time);
        my $dt = DateTime->new(
            year       => $temp[0],
            month      => $temp[1],
            day        => $temp[2],
            hour       => $temp_time[0],
            minute     => $temp_time[1],
            second     => 0,
            time_zone  => "GMT",#'Europe/Brussels'
        );
        my $result = ($dt_now->subtract_datetime_absolute($dt)->in_units('seconds') )/ (60*60);
        $result = sprintf("%.3f",$result);
        $msg = "backup instance_id = $id database_name $o_dbname is $result" . $metrics{'backup_age'} . " old"  ;
        
        if ((defined($np->opts->warning) || defined($np->opts->critical))) {
            $np->set_thresholds(warning => $o_warning, critical => $o_critical);
            my $test_metric = $np->check_threshold($result);
            push( @criticals, " backup age  out of range value $result" . $metrics{"backup_age"} ) if ($test_metric==2);
            push( @warnings, " backup age  out of range value $result" . $metrics{"backup_age"} ) if ($test_metric==1);
        } 
        

} else {
    
  
    #Getting instance info
    my $a_instance_url = "https://api.scaleway.com/rdb/$o_apiversion/regions/$o_reg/instances/$id";
    my $instance_json;
    my $rep_instance ;
    verb($a_instance_url);
    $client->GET($a_instance_url);
    if($client->responseCode() ne '200'){
        $np->plugin_exit(UNKNOWN, " response code : " . $client->responseCode() . " Message : Error when getting instance". $client->{_res}->decoded_content );
    }
    $rep_instance = $client->{_res}->decoded_content;
    $instance_json = from_json($rep_instance);
    verb(Dumper($instance_json));
    my $engine = $instance_json->{'engine'};
    my $status = $instance_json->{'status'};
    my $name =  $instance_json->{'name'};
    $max_connexions = 0;
    $msg ="instance status $status engine $engine name $name id = $id";
    $max_connexions = $instance_json->{'settings'}->[0]->{'value'} if ($instance_json->{'settings'}->[0]->{'name'} eq "max_connections");
    #If state in not defined in %state then return critical
    if (!exists $state{$status} ){
        push( @criticals," State $status is UNKNOWN "); 
    } else {
        push( @criticals,$msg) if ($state{$status}== 2);
    }
    push( @criticals,$msg) if ($state{$status}== 2);
    if ($o_metric) {
        #Metric
        my $rep_metric;
        my $patern = $o_metric;
        $patern = "total_connections" if ($o_metric eq "total_connections_percent");
        my $metric_url = "https://api.scaleway.com/rdb/$o_apiversion/regions/$o_reg/instances/$id/metrics?metric_name=$patern";
        verb($metric_url);
        $client->GET($metric_url);
        if($client->responseCode() ne '200'){
            $np->plugin_exit(UNKNOWN, " response code : " . $client->responseCode() . " Message : Error when getting instance metrics". $client->{_res}->decoded_content );
        }
        $rep_metric = $client->{_res}->decoded_content;
        my $metric_json = from_json($rep_metric);
        verb(Dumper($metric_json));
        $i=0;
        my @metric_list;
        push(@metric_list,"total_connections_percent");
        my %metrics_bdd;
        my $node;
        my $metric;
        my $j=0;
        while (exists ($metric_json->{'timeseries'}->[$i])){
            if ($patern eq $metric_json->{'timeseries'}->[$i]->{'name'}){
                $node = q{};
                $metric = q{};
                if (exists $metric_json->{'timeseries'}->[$i]->{'points'}) {
                    $node = $metric_json->{'timeseries'}->[$i]->{'metadata'}->{'node'};
                    if ($o_metric eq "total_connections_percent"){
                        $metric = $metric_json->{'timeseries'}->[$i]->{'points'}->[0]->[1];
                        if ($max_connexions==0){
                            $np->plugin_exit('UNKNOWN'," Max connexions = 0 in db settings");
                        } else {
                            $metric = sprintf("%.3f",($metric*100)/$max_connexions);
                        }
                    } else{
                        #sprintf("%.3f",$result);
                        $metric = sprintf("%.3f",$metric_json->{'timeseries'}->[$i]->{'points'}->[0]->[1]); 
                    }
                    $metrics_bdd{$node} = $metric;
                }
            } 
            $i++;  
        }
        $msg = $name;
        my @keys = keys %metrics_bdd;
        #Formaage du resultat
        my @tmp = ();
        foreach my $key (@keys) {
            @tmp = split(' ',$key);
            $msg = "$msg $key  $o_metric =  $metrics_bdd{$key}$metrics{$o_metric}";
            $np->add_perfdata(label => "$o_metric"."_". $tmp[1], value => $metrics_bdd{$key}, uom => $metrics{$o_metric}, warning => $o_warning, critical => $o_critical);
            if ((defined($np->opts->warning) || defined($np->opts->critical))) {
                $np->set_thresholds(warning => $o_warning, critical => $o_critical);
                my $test_metric = $np->check_threshold($metrics_bdd{$key});
                push( @criticals, " $o_metric $key out of range value $metrics_bdd{$key}" . $metrics{$o_metric} ) if ($test_metric==2);
                push( @warnings, " $o_metric $key out of range value $metrics_bdd{$key}" . $metrics{$o_metric}) if ($test_metric==1);
            } 
        }
        
    }
}

$np->plugin_exit('CRITICAL', join(', ', @criticals)) if (scalar @criticals > 0);
$np->plugin_exit('WARNING', join(', ', @warnings)) if (scalar @warnings > 0);
$np->plugin_exit('OK', $msg );
