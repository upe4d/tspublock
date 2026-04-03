<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Cache-Control: no-store');
define('IPSET_NAME','TSPUIPS');
define('CHAIN_NAME','TSPUBLOCK');
define('ADDED_FILE','/etc/rst_added.txt');
define('CACHE_DIR',__DIR__.'/cache/');
define('CACHE_WHOIS',24*3600);
if(!is_dir(CACHE_DIR))mkdir(CACHE_DIR,0755,true);
$action=$_GET['action']??'list';
switch($action){
  case 'list':  echo json_encode(getList(),JSON_UNESCAPED_UNICODE|JSON_PRETTY_PRINT);break;
  case 'whois': echo json_encode(getWhois(),JSON_UNESCAPED_UNICODE|JSON_PRETTY_PRINT);break;
  case 'stats': echo json_encode(getStats(),JSON_UNESCAPED_UNICODE|JSON_PRETTY_PRINT);break;
  case 'export':doExport();break;
  case 'delete':doDelete();break;
  default:http_response_code(400);echo json_encode(['error'=>'Unknown action']);
}
function getCyberokIps():array{
    $f='/etc/cyberok_ips.txt';
    if(!file_exists($f))return[];
    return array_filter(array_map(function($ip){ $ip=trim($ip); return str_ends_with($ip,'/32')?substr($ip,0,-3):$ip; }, file($f,FILE_IGNORE_NEW_LINES|FILE_SKIP_EMPTY_LINES)));
}
function getList():array{
  $raw=shell_exec('sudo ipset list '.IPSET_NAME.' 2>/dev/null');
  if(!$raw)return['error'=>'ipset недоступен','ips'=>[]];
  $ips=[];
  foreach(explode("\n",$raw)as $line){
    $line=trim($line);
    if(preg_match('/^[\d.]+(?:\/\d+)?$/',$line))$ips[]=$line;
  }
  $history=[];
  if(file_exists(ADDED_FILE)){
    foreach(file(ADDED_FILE,FILE_IGNORE_NEW_LINES|FILE_SKIP_EMPTY_LINES)as $row){
      if(preg_match('/^([\d\-]+ [\d:]+)\s+([\d.\/]+)$/',$row,$m))$history[$m[2]]=$m[1];
    }
  }
  $cyberokIps=getCyberokIps();
  $result=[];
  foreach($ips as $ip)$result[]=['ip'=>$ip,'added'=>$history[$ip]??null,'is_net'=>str_contains($ip,'//'),'source'=>in_array($ip,$cyberokIps)?'cyberok':'auto'];
  usort($result,function($a,$b){
    if($a['added']&&$b['added'])return $b['added']<=>$a['added'];
    if($a['added'])return -1;if($b['added'])return 1;
    return $a['ip']<=>$b['ip'];
  });
  return['ips'=>$result,'total'=>count($result),'updated_at'=>date('d.m.Y H:i:s', time() + 10800)];
}
function getWhois():array{
  $ip=$_GET['ip']??'';
  if(!filter_var($ip,FILTER_VALIDATE_IP,FILTER_FLAG_IPV4))return['error'=>'Неверный IP'];
  $cf=CACHE_DIR.'whois_'.str_replace('.','_',$ip).'.json';
  if(file_exists($cf)&&(time()-filemtime($cf))<CACHE_WHOIS)return json_decode(file_get_contents($cf),true);
  $raw=shell_exec("whois ".escapeshellarg($ip)." 2>/dev/null");
  $data=['ip'=>$ip,'org'=>ew($raw,['org-name','OrgName','owner']),'netname'=>ew($raw,['netname','NetName']),'descr'=>ew($raw,['descr']),'country'=>ew($raw,['country','Country']),'abuse'=>ew($raw,['abuse-mailbox','OrgAbuseEmail'])];
  $text=strtolower($data['org'].' '.$data['netname'].' '.$data['descr']);
  $data['type']='unknown';
  foreach(['cyberok','skipa','нкцки','грчц','эшелон']as $kw)if(str_contains($text,$kw)){$data['type']='tspublock';break;}
  if($data['type']==='unknown'){
    foreach(['megafon','мегафон','mts','мтс','beeline','билайн','tele2','vimpelcom','ttk','dom.ru','er-telecom']as $kw)if(str_contains($text,$kw)){$data['type']='operator';break;}
  }
  if($data['type']==='unknown'&&$data['country']==='RU')$data['type']='ru_unknown';
  file_put_contents($cf,json_encode($data,JSON_UNESCAPED_UNICODE));
  return $data;
}
function ew(?string $raw,array $fields):string{
  if(!$raw)return'';
  foreach($fields as $f)if(preg_match('/^'.preg_quote($f,'/').'\\s*:\\s*(.+)$/mi',$raw,$m))return trim($m[1]);
  return'';
}
function getStats():array{
  $pkts=0;$bytes=0;
  $raw=shell_exec('sudo iptables -L '.CHAIN_NAME.' -v -n 2>/dev/null');
  if($raw&&preg_match('/(\d+)\s+([\d.]+[KMG]?)\s+DROP/m',$raw,$m)){$pkts=(int)$m[1];$braw=$m[2];if(str_ends_with($braw,"K")){$bytes=(int)((float)$braw*1024);}elseif(str_ends_with($braw,"M")){$bytes=(int)((float)$braw*1048576);}elseif(str_ends_with($braw,"G")){$bytes=(int)((float)$braw*1073741824);}else{$bytes=(int)$braw;}}
  $raw2=shell_exec('sudo ipset list '.IPSET_NAME.' 2>/dev/null');
  $cnt=$raw2?max(0,substr_count($raw2,"\n")-8):0;
  $last=null;
  if(file_exists(ADDED_FILE)){$ls=file(ADDED_FILE,FILE_IGNORE_NEW_LINES|FILE_SKIP_EMPTY_LINES);if($ls){$l=end($ls);if(preg_match('/^([\d\-]+ [\d:]+)/',$l,$m))$last=$m[1];}}
  $fb=function(int $b):string{if($b>=1073741824)return round($b/1073741824,2).' GB';if($b>=1048576)return round($b/1048576,2).' MB';if($b>=1024)return round($b/1024,1).' KB';return $b.' B';};
  return['blocked_packets'=>$pkts,'blocked_bytes'=>$bytes,'blocked_bytes_h'=>$fb($bytes),'ip_count'=>$cnt,'last_updated'=>$last,'chain_active'=>(bool)$raw,'updated_at'=>date('d.m.Y H:i:s', time() + 10800)];
}
function doDelete():void{
    header('Content-Type: application/json');
    $ip = $_GET['ip'] ?? '';
    $token = $_GET['token'] ?? '';
    if($token !== 'upe4d_rst_2026'){http_response_code(403);echo json_encode(['error'=>'bad token']);return;}
    if(!filter_var($ip,FILTER_VALIDATE_IP,FILTER_FLAG_IPV4)){echo json_encode(['error'=>'bad ip']);return;}
    // Удаляем из ipset
    shell_exec('sudo ipset del TSPUIPS '.escapeshellarg($ip).' 2>/dev/null');
    // Удаляем из логов
    foreach(['/etc/rst_added.txt','/etc/rst_submitted.txt','/etc/cyberok_added.txt']as $f){
        if(file_exists($f)){
            $lines=file($f,FILE_IGNORE_NEW_LINES|FILE_SKIP_EMPTY_LINES);
            $lines=array_filter($lines,fn($l)=>!str_contains($l,$ip));
            file_put_contents($f,implode("
",$lines)."
");
        }
    }
    shell_exec('sudo ipset save > /etc/ipset.conf');
    echo json_encode(['ok'=>true,'ip'=>$ip,'msg'=>'IP удалён из базы']);
}
function doExport():void{
  $fmt=$_GET['fmt']??'txt';
  $data=getList();$ips=array_column($data['ips'],'ip');
  if($fmt==='txt'){header('Content-Type: text/plain');header('Content-Disposition: attachment; filename="tspuips.txt"');echo "# ТСПУ RST блок-лист | stats.gptru.pro/rst | ".date('Y-m-d', time()+10800)."\n# Всего: ".count($ips)."\n\n".implode("\n",$ips);}
  elseif($fmt==='mikrotik'){header('Content-Type: text/plain');header('Content-Disposition: attachment; filename="tspuips_mikrotik.rsc"');echo "# ТСПУ RST блок-лист для MikroTik\n/ip firewall address-list remove [find list=TSPUIPS]\n";foreach($ips as $ip)echo "/ip firewall address-list add list=TSPUIPS address={$ip}\n";}
  elseif($fmt==='iptables'){header('Content-Type: text/plain');header('Content-Disposition: attachment; filename="tspuips_iptables.sh"');echo "#!/bin/bash\n# ТСПУ RST блок-лист | stats.gptru.pro/rst\niptables-save > /tmp/iptables_backup.rules\nipset destroy TSPUIPS 2>/dev/null\nipset create TSPUIPS hash:net maxelem 1024\n";foreach($ips as $ip)echo "ipset add TSPUIPS {$ip}\n";echo "iptables -N TSPUBLOCK 2>/dev/null\niptables -F TSPUBLOCK\niptables -A TSPUBLOCK -p tcp --tcp-flags RST RST -m set --match-set TSPUIPS src -j DROP\niptables -C INPUT -j TSPUBLOCK 2>/dev/null || iptables -I INPUT 1 -j TSPUBLOCK\nipset save > /etc/ipset.conf\niptables-save > /etc/iptables/rules.v4\necho \"Готово: \$(ipset list TSPUIPS | grep -c '^[0-9]') IP\"\n";}
  elseif($fmt==='ipset'){header('Content-Type: text/plain');header('Content-Disposition: attachment; filename="tspuips.ipset"');echo "create TSPUIPS hash:net family inet hashsize 1024 maxelem 1024\n";foreach($ips as $ip)echo "add TSPUIPS {$ip}\n";}
  else{header('Content-Type: application/json');echo json_encode(['error'=>'Форматы: txt, mikrotik, iptables, ipset']);}
}
