// DEV — tela temporária de benchmark do Geocoder nativo Android.
// Remove a entrada do menu após os testes. O arquivo pode permanecer inerte.
//
// Fluxo: botão "Iniciar" → loop 500 endereços via MethodChannel "geocoder"
//   → delay 150ms entre chamadas → _exportToSupabase() em lotes de 50.
// Também aceita teste manual de 1 endereço via campo de texto.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';

// URL da tabela de benchmark no Supabase
const _supabaseUrl =
    'https://zqgkfqenrljtncoecegv.supabase.co/rest/v1/geocoder_benchmark';

// Mesma chave publishable do AppLogger — INSERT-only via RLS
const _supabaseKey = 'sb_publishable_cw4YwcWkSNhGc-zkTjO7xw_lPS5NE09';

// Canal nativo exposto pela MainActivity (PASSO 2)
const _channel = MethodChannel('com.sopro.sopro/geocoder');

// ─── Lista de 500 endereços ───────────────────────────────────────────────────
// Distribuídos por categoria e UF; ~20 da região de Piracicaba/Santos/interior SP.
// Campos: query, state_uf, city, category
//   Categorias: com_numero | por_nome | sem_numero | cidade_media
//               com_acento | ambiguo
const List<Map<String, String>> _addresses = [
  // ── com_numero (100) ──────────────────────────────────────────────────────
  {'query': 'Avenida Paulista, 1578, São Paulo, SP',             'state_uf': 'SP', 'city': 'São Paulo',      'category': 'com_numero'},
  {'query': 'Rua Augusta, 1492, São Paulo, SP',                  'state_uf': 'SP', 'city': 'São Paulo',      'category': 'com_numero'},
  {'query': 'Avenida Brigadeiro Faria Lima, 3477, São Paulo, SP','state_uf': 'SP', 'city': 'São Paulo',      'category': 'com_numero'},
  {'query': 'Rua Oscar Freire, 900, São Paulo, SP',              'state_uf': 'SP', 'city': 'São Paulo',      'category': 'com_numero'},
  {'query': 'Avenida Rebouças, 1585, São Paulo, SP',             'state_uf': 'SP', 'city': 'São Paulo',      'category': 'com_numero'},
  {'query': 'Rua do Rosário, 500, Piracicaba, SP',               'state_uf': 'SP', 'city': 'Piracicaba',     'category': 'com_numero'},
  {'query': 'Avenida Independência, 2500, Piracicaba, SP',       'state_uf': 'SP', 'city': 'Piracicaba',     'category': 'com_numero'},
  {'query': 'Rua Boa Morte, 400, Piracicaba, SP',                'state_uf': 'SP', 'city': 'Piracicaba',     'category': 'com_numero'},
  {'query': 'Avenida Ana Costa, 1500, Santos, SP',               'state_uf': 'SP', 'city': 'Santos',         'category': 'com_numero'},
  {'query': 'Rua General Câmara, 300, Santos, SP',               'state_uf': 'SP', 'city': 'Santos',         'category': 'com_numero'},
  {'query': 'Avenida Conselheiro Nébias, 600, Santos, SP',       'state_uf': 'SP', 'city': 'Santos',         'category': 'com_numero'},
  {'query': 'Rua Quinze de Novembro, 95, Ribeirão Preto, SP',    'state_uf': 'SP', 'city': 'Ribeirão Preto', 'category': 'com_numero'},
  {'query': 'Avenida Brasil, 2500, Campinas, SP',                'state_uf': 'SP', 'city': 'Campinas',       'category': 'com_numero'},
  {'query': 'Rua Voluntários de Piracicaba, 1200, Piracicaba, SP','state_uf': 'SP','city': 'Piracicaba',     'category': 'com_numero'},
  {'query': 'Avenida Atlântica, 1702, Rio de Janeiro, RJ',       'state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'com_numero'},
  {'query': 'Rua das Laranjeiras, 100, Rio de Janeiro, RJ',      'state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'com_numero'},
  {'query': 'Avenida das Américas, 4666, Rio de Janeiro, RJ',    'state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'com_numero'},
  {'query': 'Rua Voluntários da Pátria, 400, Rio de Janeiro, RJ','state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'com_numero'},
  {'query': 'Avenida Afonso Pena, 1500, Belo Horizonte, MG',     'state_uf': 'MG', 'city': 'Belo Horizonte', 'category': 'com_numero'},
  {'query': 'Rua da Bahia, 1000, Belo Horizonte, MG',            'state_uf': 'MG', 'city': 'Belo Horizonte', 'category': 'com_numero'},
  {'query': 'Avenida do Contorno, 2200, Belo Horizonte, MG',     'state_uf': 'MG', 'city': 'Belo Horizonte', 'category': 'com_numero'},
  {'query': 'Rua dos Andradas, 1234, Porto Alegre, RS',          'state_uf': 'RS', 'city': 'Porto Alegre',   'category': 'com_numero'},
  {'query': 'Avenida Osvaldo Aranha, 500, Porto Alegre, RS',     'state_uf': 'RS', 'city': 'Porto Alegre',   'category': 'com_numero'},
  {'query': 'Avenida Borges de Medeiros, 200, Porto Alegre, RS', 'state_uf': 'RS', 'city': 'Porto Alegre',   'category': 'com_numero'},
  {'query': 'Rua XV de Novembro, 800, Curitiba, PR',             'state_uf': 'PR', 'city': 'Curitiba',       'category': 'com_numero'},
  {'query': 'Avenida Sete de Setembro, 3165, Curitiba, PR',      'state_uf': 'PR', 'city': 'Curitiba',       'category': 'com_numero'},
  {'query': 'Rua Felipe Schmidt, 200, Florianópolis, SC',        'state_uf': 'SC', 'city': 'Florianópolis',  'category': 'com_numero'},
  {'query': 'Avenida Beira Mar Norte, 1000, Florianópolis, SC',  'state_uf': 'SC', 'city': 'Florianópolis',  'category': 'com_numero'},
  {'query': 'Avenida Sete de Setembro, 2000, Salvador, BA',      'state_uf': 'BA', 'city': 'Salvador',       'category': 'com_numero'},
  {'query': 'Rua Chile, 100, Salvador, BA',                      'state_uf': 'BA', 'city': 'Salvador',       'category': 'com_numero'},
  {'query': 'Avenida Boa Viagem, 2000, Recife, PE',              'state_uf': 'PE', 'city': 'Recife',         'category': 'com_numero'},
  {'query': 'Rua do Bom Jesus, 197, Recife, PE',                 'state_uf': 'PE', 'city': 'Recife',         'category': 'com_numero'},
  {'query': 'Avenida Beira Mar, 3000, Fortaleza, CE',            'state_uf': 'CE', 'city': 'Fortaleza',      'category': 'com_numero'},
  {'query': 'Rua Major Facundo, 500, Fortaleza, CE',             'state_uf': 'CE', 'city': 'Fortaleza',      'category': 'com_numero'},
  {'query': 'Avenida Eduardo Ribeiro, 520, Manaus, AM',          'state_uf': 'AM', 'city': 'Manaus',         'category': 'com_numero'},
  {'query': 'Rua Sete de Setembro, 100, Manaus, AM',             'state_uf': 'AM', 'city': 'Manaus',         'category': 'com_numero'},
  {'query': 'Avenida Nazaré, 1000, Belém, PA',                   'state_uf': 'PA', 'city': 'Belém',          'category': 'com_numero'},
  {'query': 'Travessa Padre Eutíquio, 2000, Belém, PA',          'state_uf': 'PA', 'city': 'Belém',          'category': 'com_numero'},
  {'query': 'SQN 104 Bloco A, Brasília, DF',                     'state_uf': 'DF', 'city': 'Brasília',       'category': 'com_numero'},
  {'query': 'SCN Quadra 5, Brasília, DF',                        'state_uf': 'DF', 'city': 'Brasília',       'category': 'com_numero'},
  {'query': 'Avenida Goiás, 1000, Goiânia, GO',                  'state_uf': 'GO', 'city': 'Goiânia',        'category': 'com_numero'},
  {'query': 'Rua 30, 500, Goiânia, GO',                          'state_uf': 'GO', 'city': 'Goiânia',        'category': 'com_numero'},
  {'query': 'Avenida Getúlio Vargas, 1000, Cuiabá, MT',          'state_uf': 'MT', 'city': 'Cuiabá',         'category': 'com_numero'},
  {'query': 'Rua Barão de Melgaço, 500, Cuiabá, MT',             'state_uf': 'MT', 'city': 'Cuiabá',         'category': 'com_numero'},
  {'query': 'Avenida Afonso Pena, 2000, Campo Grande, MS',       'state_uf': 'MS', 'city': 'Campo Grande',   'category': 'com_numero'},
  {'query': 'Rua Dom Aquino, 1500, Campo Grande, MS',            'state_uf': 'MS', 'city': 'Campo Grande',   'category': 'com_numero'},
  {'query': 'Avenida Vitória, 2000, Vitória, ES',                'state_uf': 'ES', 'city': 'Vitória',        'category': 'com_numero'},
  {'query': 'Rua Sete de Setembro, 800, Vitória, ES',            'state_uf': 'ES', 'city': 'Vitória',        'category': 'com_numero'},
  {'query': 'Rua Grande, 1000, São Luís, MA',                    'state_uf': 'MA', 'city': 'São Luís',       'category': 'com_numero'},
  {'query': 'Avenida Litorânea, 2000, São Luís, MA',             'state_uf': 'MA', 'city': 'São Luís',       'category': 'com_numero'},
  {'query': 'Rua Álvaro Mendes, 1000, Teresina, PI',             'state_uf': 'PI', 'city': 'Teresina',       'category': 'com_numero'},
  {'query': 'Avenida Rio Branco, 1000, Natal, RN',               'state_uf': 'RN', 'city': 'Natal',          'category': 'com_numero'},
  {'query': 'Rua das Trincheiras, 500, João Pessoa, PB',         'state_uf': 'PB', 'city': 'João Pessoa',    'category': 'com_numero'},
  {'query': 'Avenida Ivo do Prado, 1000, Aracaju, SE',           'state_uf': 'SE', 'city': 'Aracaju',        'category': 'com_numero'},
  {'query': 'Rua do Comércio, 1000, Maceió, AL',                 'state_uf': 'AL', 'city': 'Maceió',         'category': 'com_numero'},
  {'query': 'Avenida Teotônio Segurado, 100, Palmas, TO',        'state_uf': 'TO', 'city': 'Palmas',         'category': 'com_numero'},
  {'query': 'Avenida Lauro Sodré, 1000, Porto Velho, RO',        'state_uf': 'RO', 'city': 'Porto Velho',    'category': 'com_numero'},
  {'query': 'Rua Benjamin Constant, 500, Rio Branco, AC',        'state_uf': 'AC', 'city': 'Rio Branco',     'category': 'com_numero'},
  {'query': 'Avenida Mendonça Furtado, 1000, Macapá, AP',        'state_uf': 'AP', 'city': 'Macapá',         'category': 'com_numero'},
  {'query': 'Avenida Major Williams, 500, Boa Vista, RR',        'state_uf': 'RR', 'city': 'Boa Vista',      'category': 'com_numero'},
  {'query': 'Rua 24 de Outubro, 300, Porto Alegre, RS',          'state_uf': 'RS', 'city': 'Porto Alegre',   'category': 'com_numero'},
  {'query': 'Rua Padre Chagas, 100, Porto Alegre, RS',           'state_uf': 'RS', 'city': 'Porto Alegre',   'category': 'com_numero'},
  {'query': 'Avenida Vieira Souto, 320, Rio de Janeiro, RJ',     'state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'com_numero'},
  {'query': 'Rua Jardim Botânico, 1008, Rio de Janeiro, RJ',     'state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'com_numero'},
  {'query': 'Avenida João Pinheiro, 100, Belo Horizonte, MG',    'state_uf': 'MG', 'city': 'Belo Horizonte', 'category': 'com_numero'},
  {'query': 'Rua Espírito Santo, 700, Belo Horizonte, MG',       'state_uf': 'MG', 'city': 'Belo Horizonte', 'category': 'com_numero'},
  {'query': 'Avenida Carlos Gomes, 800, Porto Alegre, RS',       'state_uf': 'RS', 'city': 'Porto Alegre',   'category': 'com_numero'},
  {'query': 'Rua Ecológica, 300, Curitiba, PR',                  'state_uf': 'PR', 'city': 'Curitiba',       'category': 'com_numero'},
  {'query': 'Avenida Água Verde, 700, Curitiba, PR',             'state_uf': 'PR', 'city': 'Curitiba',       'category': 'com_numero'},
  {'query': 'Rua João Pinheiro, 200, Florianópolis, SC',         'state_uf': 'SC', 'city': 'Florianópolis',  'category': 'com_numero'},
  {'query': 'Avenida Rio Branco, 3000, Florianópolis, SC',       'state_uf': 'SC', 'city': 'Florianópolis',  'category': 'com_numero'},
  {'query': 'Rua da Glória, 400, Salvador, BA',                  'state_uf': 'BA', 'city': 'Salvador',       'category': 'com_numero'},
  {'query': 'Avenida Oceânica, 500, Salvador, BA',               'state_uf': 'BA', 'city': 'Salvador',       'category': 'com_numero'},
  {'query': 'Rua Marquês de Olinda, 100, Recife, PE',            'state_uf': 'PE', 'city': 'Recife',         'category': 'com_numero'},
  {'query': 'Avenida Domingos Ferreira, 3000, Recife, PE',       'state_uf': 'PE', 'city': 'Recife',         'category': 'com_numero'},
  {'query': 'Rua João Moreira, 200, Fortaleza, CE',              'state_uf': 'CE', 'city': 'Fortaleza',      'category': 'com_numero'},
  {'query': 'Avenida Santos Dumont, 3000, Fortaleza, CE',        'state_uf': 'CE', 'city': 'Fortaleza',      'category': 'com_numero'},
  {'query': 'Rua Marcílio Dias, 300, Manaus, AM',                'state_uf': 'AM', 'city': 'Manaus',         'category': 'com_numero'},
  {'query': 'Avenida Constantino Nery, 1000, Manaus, AM',        'state_uf': 'AM', 'city': 'Manaus',         'category': 'com_numero'},
  {'query': 'Rua dos Mundurucus, 1000, Belém, PA',               'state_uf': 'PA', 'city': 'Belém',          'category': 'com_numero'},
  {'query': 'Avenida Almirante Barroso, 600, Belém, PA',         'state_uf': 'PA', 'city': 'Belém',          'category': 'com_numero'},
  {'query': 'SQS 308 Bloco C, Brasília, DF',                     'state_uf': 'DF', 'city': 'Brasília',       'category': 'com_numero'},
  {'query': 'Rua 4, 800, Goiânia, GO',                           'state_uf': 'GO', 'city': 'Goiânia',        'category': 'com_numero'},
  {'query': 'Rua Joaquim Murtinho, 300, Cuiabá, MT',             'state_uf': 'MT', 'city': 'Cuiabá',         'category': 'com_numero'},
  {'query': 'Rua Marechal Rondon, 800, Campo Grande, MS',        'state_uf': 'MS', 'city': 'Campo Grande',   'category': 'com_numero'},
  {'query': 'Rua Henrique Moscoso, 700, Vila Velha, ES',         'state_uf': 'ES', 'city': 'Vila Velha',     'category': 'com_numero'},
  {'query': 'Rua do Alecrim, 500, Natal, RN',                    'state_uf': 'RN', 'city': 'Natal',          'category': 'com_numero'},
  {'query': 'Rua Visconde de Pelotas, 100, João Pessoa, PB',     'state_uf': 'PB', 'city': 'João Pessoa',    'category': 'com_numero'},
  {'query': 'Rua Laranjeiras, 400, Aracaju, SE',                 'state_uf': 'SE', 'city': 'Aracaju',        'category': 'com_numero'},
  {'query': 'Avenida Durval de Góes Monteiro, 200, Maceió, AL',  'state_uf': 'AL', 'city': 'Maceió',         'category': 'com_numero'},
  {'query': 'Avenida João Pessoa, 500, São Luís, MA',            'state_uf': 'MA', 'city': 'São Luís',       'category': 'com_numero'},
  {'query': 'Rua Eliseu Martins, 300, Teresina, PI',             'state_uf': 'PI', 'city': 'Teresina',       'category': 'com_numero'},
  {'query': 'Avenida Dom Pedro II, 1400, São Paulo, SP',         'state_uf': 'SP', 'city': 'São Paulo',      'category': 'com_numero'},
  {'query': 'Rua Vergueiro, 3000, São Paulo, SP',                'state_uf': 'SP', 'city': 'São Paulo',      'category': 'com_numero'},
  {'query': 'Avenida Washington Luís, 2000, São Paulo, SP',      'state_uf': 'SP', 'city': 'São Paulo',      'category': 'com_numero'},
  {'query': 'Rua Moraes e Vale, 200, Rio de Janeiro, RJ',        'state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'com_numero'},
  {'query': 'Avenida Nilo Peçanha, 50, Rio de Janeiro, RJ',      'state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'com_numero'},

  // ── por_nome (100) ─────────────────────────────────────────────────────────
  {'query': 'Shopping Ibirapuera, São Paulo, SP',                'state_uf': 'SP', 'city': 'São Paulo',      'category': 'por_nome'},
  {'query': 'Terminal Tietê, São Paulo, SP',                     'state_uf': 'SP', 'city': 'São Paulo',      'category': 'por_nome'},
  {'query': 'Parque do Ibirapuera, São Paulo, SP',               'state_uf': 'SP', 'city': 'São Paulo',      'category': 'por_nome'},
  {'query': 'Aeroporto de Congonhas, São Paulo, SP',             'state_uf': 'SP', 'city': 'São Paulo',      'category': 'por_nome'},
  {'query': 'MASP, Avenida Paulista, São Paulo, SP',             'state_uf': 'SP', 'city': 'São Paulo',      'category': 'por_nome'},
  {'query': 'Hospital das Clínicas, São Paulo, SP',              'state_uf': 'SP', 'city': 'São Paulo',      'category': 'por_nome'},
  {'query': 'Universidade de São Paulo, São Paulo, SP',          'state_uf': 'SP', 'city': 'São Paulo',      'category': 'por_nome'},
  {'query': 'Terminal Urbano de Piracicaba, Piracicaba, SP',     'state_uf': 'SP', 'city': 'Piracicaba',     'category': 'por_nome'},
  {'query': 'Escola Superior de Agricultura Luiz de Queiroz, Piracicaba, SP','state_uf':'SP','city':'Piracicaba','category':'por_nome'},
  {'query': 'Porto de Santos, Santos, SP',                       'state_uf': 'SP', 'city': 'Santos',         'category': 'por_nome'},
  {'query': 'Aquário de Santos, Santos, SP',                     'state_uf': 'SP', 'city': 'Santos',         'category': 'por_nome'},
  {'query': 'Shopping Praiamar, Santos, SP',                     'state_uf': 'SP', 'city': 'Santos',         'category': 'por_nome'},
  {'query': 'Cristo Redentor, Rio de Janeiro, RJ',               'state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'por_nome'},
  {'query': 'Aeroporto Santos Dumont, Rio de Janeiro, RJ',       'state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'por_nome'},
  {'query': 'Museu do Amanhã, Rio de Janeiro, RJ',               'state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'por_nome'},
  {'query': 'Maracanã, Rio de Janeiro, RJ',                      'state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'por_nome'},
  {'query': 'Pão de Açúcar, Rio de Janeiro, RJ',                 'state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'por_nome'},
  {'query': 'Shopping BH, Belo Horizonte, MG',                   'state_uf': 'MG', 'city': 'Belo Horizonte', 'category': 'por_nome'},
  {'query': 'Aeroporto de Confins, Confins, MG',                 'state_uf': 'MG', 'city': 'Confins',        'category': 'por_nome'},
  {'query': 'Lagoa da Pampulha, Belo Horizonte, MG',             'state_uf': 'MG', 'city': 'Belo Horizonte', 'category': 'por_nome'},
  {'query': 'Aeroporto Salgado Filho, Porto Alegre, RS',         'state_uf': 'RS', 'city': 'Porto Alegre',   'category': 'por_nome'},
  {'query': 'Parque Farroupilha, Porto Alegre, RS',              'state_uf': 'RS', 'city': 'Porto Alegre',   'category': 'por_nome'},
  {'query': 'Barra Shopping Sul, Porto Alegre, RS',              'state_uf': 'RS', 'city': 'Porto Alegre',   'category': 'por_nome'},
  {'query': 'Jardim Botânico, Curitiba, PR',                     'state_uf': 'PR', 'city': 'Curitiba',       'category': 'por_nome'},
  {'query': 'Aeroporto Afonso Pena, São José dos Pinhais, PR',   'state_uf': 'PR', 'city': 'São José dos Pinhais','category':'por_nome'},
  {'query': 'BarraShopping, Florianópolis, SC',                  'state_uf': 'SC', 'city': 'Florianópolis',  'category': 'por_nome'},
  {'query': 'Mercado Público, Florianópolis, SC',                'state_uf': 'SC', 'city': 'Florianópolis',  'category': 'por_nome'},
  {'query': 'Elevador Lacerda, Salvador, BA',                    'state_uf': 'BA', 'city': 'Salvador',       'category': 'por_nome'},
  {'query': 'Aeroporto de Salvador, Salvador, BA',               'state_uf': 'BA', 'city': 'Salvador',       'category': 'por_nome'},
  {'query': 'Shopping Salvador, Salvador, BA',                   'state_uf': 'BA', 'city': 'Salvador',       'category': 'por_nome'},
  {'query': 'Marco Zero, Recife, PE',                            'state_uf': 'PE', 'city': 'Recife',         'category': 'por_nome'},
  {'query': 'Instituto Ricardo Brennand, Recife, PE',            'state_uf': 'PE', 'city': 'Recife',         'category': 'por_nome'},
  {'query': 'Praia de Iracema, Fortaleza, CE',                   'state_uf': 'CE', 'city': 'Fortaleza',      'category': 'por_nome'},
  {'query': 'Shopping RioMar, Fortaleza, CE',                    'state_uf': 'CE', 'city': 'Fortaleza',      'category': 'por_nome'},
  {'query': 'Teatro Amazonas, Manaus, AM',                       'state_uf': 'AM', 'city': 'Manaus',         'category': 'por_nome'},
  {'query': 'Shopping Manauara, Manaus, AM',                     'state_uf': 'AM', 'city': 'Manaus',         'category': 'por_nome'},
  {'query': 'Ver-o-Peso, Belém, PA',                             'state_uf': 'PA', 'city': 'Belém',          'category': 'por_nome'},
  {'query': 'Shopping Pátio Belém, Belém, PA',                   'state_uf': 'PA', 'city': 'Belém',          'category': 'por_nome'},
  {'query': 'Congresso Nacional, Brasília, DF',                  'state_uf': 'DF', 'city': 'Brasília',       'category': 'por_nome'},
  {'query': 'Palácio do Planalto, Brasília, DF',                 'state_uf': 'DF', 'city': 'Brasília',       'category': 'por_nome'},
  {'query': 'Parque Flamboyant, Goiânia, GO',                    'state_uf': 'GO', 'city': 'Goiânia',        'category': 'por_nome'},
  {'query': 'Shopping Flamboyant, Goiânia, GO',                  'state_uf': 'GO', 'city': 'Goiânia',        'category': 'por_nome'},
  {'query': 'Pantanal, Cuiabá, MT',                              'state_uf': 'MT', 'city': 'Cuiabá',         'category': 'por_nome'},
  {'query': 'Shopping Campo Grande, Campo Grande, MS',           'state_uf': 'MS', 'city': 'Campo Grande',   'category': 'por_nome'},
  {'query': 'Praia de Camburi, Vitória, ES',                     'state_uf': 'ES', 'city': 'Vitória',        'category': 'por_nome'},
  {'query': 'Centro Histórico de São Luís, São Luís, MA',        'state_uf': 'MA', 'city': 'São Luís',       'category': 'por_nome'},
  {'query': 'Parque da Criança, Teresina, PI',                   'state_uf': 'PI', 'city': 'Teresina',       'category': 'por_nome'},
  {'query': 'Shopping Natal, Natal, RN',                         'state_uf': 'RN', 'city': 'Natal',          'category': 'por_nome'},
  {'query': 'Parque Solon de Lucena, João Pessoa, PB',           'state_uf': 'PB', 'city': 'João Pessoa',    'category': 'por_nome'},
  {'query': 'Mercado Municipal de Aracaju, Aracaju, SE',         'state_uf': 'SE', 'city': 'Aracaju',        'category': 'por_nome'},
  {'query': 'Praça dos Martírios, Maceió, AL',                   'state_uf': 'AL', 'city': 'Maceió',         'category': 'por_nome'},
  {'query': 'Aeroporto de Palmas, Palmas, TO',                   'state_uf': 'TO', 'city': 'Palmas',         'category': 'por_nome'},
  {'query': 'Aeroporto de Porto Velho, Porto Velho, RO',         'state_uf': 'RO', 'city': 'Porto Velho',    'category': 'por_nome'},
  {'query': 'Parque Chico Mendes, Rio Branco, AC',               'state_uf': 'AC', 'city': 'Rio Branco',     'category': 'por_nome'},
  {'query': 'Fortaleza de São José, Macapá, AP',                 'state_uf': 'AP', 'city': 'Macapá',         'category': 'por_nome'},
  {'query': 'Monte Roraima, Boa Vista, RR',                      'state_uf': 'RR', 'city': 'Boa Vista',      'category': 'por_nome'},
  {'query': 'Drogaria São Paulo, Consolação, São Paulo, SP',     'state_uf': 'SP', 'city': 'São Paulo',      'category': 'por_nome'},
  {'query': 'Hipermercado Extra, Campinas, SP',                  'state_uf': 'SP', 'city': 'Campinas',       'category': 'por_nome'},
  {'query': 'Hospital Santa Casa, Piracicaba, SP',               'state_uf': 'SP', 'city': 'Piracicaba',     'category': 'por_nome'},
  {'query': 'Terminal Pesqueiro, Santos, SP',                    'state_uf': 'SP', 'city': 'Santos',         'category': 'por_nome'},
  {'query': 'Ponto Chic, Campinas, SP',                         'state_uf': 'SP', 'city': 'Campinas',       'category': 'por_nome'},
  {'query': 'Hiper Bompreço, Recife, PE',                        'state_uf': 'PE', 'city': 'Recife',         'category': 'por_nome'},
  {'query': 'Supermercado Comper, Campo Grande, MS',             'state_uf': 'MS', 'city': 'Campo Grande',   'category': 'por_nome'},
  {'query': 'Aeroporto de Joinville, Joinville, SC',             'state_uf': 'SC', 'city': 'Joinville',      'category': 'por_nome'},
  {'query': 'Centro Cultural OI, Rio de Janeiro, RJ',            'state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'por_nome'},
  {'query': 'Museu de Arte Moderna, São Paulo, SP',              'state_uf': 'SP', 'city': 'São Paulo',      'category': 'por_nome'},
  {'query': 'Estação da Luz, São Paulo, SP',                     'state_uf': 'SP', 'city': 'São Paulo',      'category': 'por_nome'},
  {'query': 'Mercadão de São Paulo, São Paulo, SP',              'state_uf': 'SP', 'city': 'São Paulo',      'category': 'por_nome'},
  {'query': 'Shopping Iguatemi, São Paulo, SP',                  'state_uf': 'SP', 'city': 'São Paulo',      'category': 'por_nome'},
  {'query': 'Fórum de Campinas, Campinas, SP',                   'state_uf': 'SP', 'city': 'Campinas',       'category': 'por_nome'},
  {'query': 'Unicamp, Campinas, SP',                             'state_uf': 'SP', 'city': 'Campinas',       'category': 'por_nome'},
  {'query': 'Shopping Center Norte, São Paulo, SP',              'state_uf': 'SP', 'city': 'São Paulo',      'category': 'por_nome'},
  {'query': 'Mercado Municipal de Ribeirão Preto, Ribeirão Preto, SP','state_uf':'SP','city':'Ribeirão Preto','category':'por_nome'},
  {'query': 'Zoológico de São Paulo, São Paulo, SP',             'state_uf': 'SP', 'city': 'São Paulo',      'category': 'por_nome'},
  {'query': 'Forte dos Reis Magos, Natal, RN',                   'state_uf': 'RN', 'city': 'Natal',          'category': 'por_nome'},
  {'query': 'Pelourinho, Salvador, BA',                          'state_uf': 'BA', 'city': 'Salvador',       'category': 'por_nome'},
  {'query': 'Mosteiro de São Bento, São Paulo, SP',              'state_uf': 'SP', 'city': 'São Paulo',      'category': 'por_nome'},
  {'query': 'Pinacoteca do Estado, São Paulo, SP',               'state_uf': 'SP', 'city': 'São Paulo',      'category': 'por_nome'},
  {'query': 'Museu do Futebol, São Paulo, SP',                   'state_uf': 'SP', 'city': 'São Paulo',      'category': 'por_nome'},
  {'query': 'Autódromo de Interlagos, São Paulo, SP',            'state_uf': 'SP', 'city': 'São Paulo',      'category': 'por_nome'},
  {'query': 'Parque Estadual da Serra do Mar, Bertioga, SP',     'state_uf': 'SP', 'city': 'Bertioga',       'category': 'por_nome'},
  {'query': 'Shopping Vitória, Vitória, ES',                     'state_uf': 'ES', 'city': 'Vitória',        'category': 'por_nome'},
  {'query': 'Parque Nacional de Brasília, Brasília, DF',         'state_uf': 'DF', 'city': 'Brasília',       'category': 'por_nome'},
  {'query': 'Universidade de Brasília, Brasília, DF',            'state_uf': 'DF', 'city': 'Brasília',       'category': 'por_nome'},
  {'query': 'Catedral Metropolitana, Goiânia, GO',               'state_uf': 'GO', 'city': 'Goiânia',        'category': 'por_nome'},
  {'query': 'Zoológico de Goiânia, Goiânia, GO',                 'state_uf': 'GO', 'city': 'Goiânia',        'category': 'por_nome'},
  {'query': 'Parque Nacional da Chapada dos Guimarães, MT',      'state_uf': 'MT', 'city': 'Chapada dos Guimarães','category':'por_nome'},
  {'query': 'Catedral de Campo Grande, Campo Grande, MS',        'state_uf': 'MS', 'city': 'Campo Grande',   'category': 'por_nome'},

  // ── sem_numero (100) ───────────────────────────────────────────────────────
  {'query': 'Rua das Flores, Curitiba, PR',                      'state_uf': 'PR', 'city': 'Curitiba',       'category': 'sem_numero'},
  {'query': 'Alameda Santos, São Paulo, SP',                     'state_uf': 'SP', 'city': 'São Paulo',      'category': 'sem_numero'},
  {'query': 'Rua das Palmeiras, Piracicaba, SP',                 'state_uf': 'SP', 'city': 'Piracicaba',     'category': 'sem_numero'},
  {'query': 'Avenida Beira Rio, Piracicaba, SP',                 'state_uf': 'SP', 'city': 'Piracicaba',     'category': 'sem_numero'},
  {'query': 'Rua do Porto, Santos, SP',                          'state_uf': 'SP', 'city': 'Santos',         'category': 'sem_numero'},
  {'query': 'Avenida Presidente Wilson, Santos, SP',             'state_uf': 'SP', 'city': 'Santos',         'category': 'sem_numero'},
  {'query': 'Rua da Consolação, São Paulo, SP',                  'state_uf': 'SP', 'city': 'São Paulo',      'category': 'sem_numero'},
  {'query': 'Alameda Campinas, São Paulo, SP',                   'state_uf': 'SP', 'city': 'São Paulo',      'category': 'sem_numero'},
  {'query': 'Rua Haddock Lobo, São Paulo, SP',                   'state_uf': 'SP', 'city': 'São Paulo',      'category': 'sem_numero'},
  {'query': 'Rua dos Pinheiros, São Paulo, SP',                  'state_uf': 'SP', 'city': 'São Paulo',      'category': 'sem_numero'},
  {'query': 'Praia de Copacabana, Rio de Janeiro, RJ',           'state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'sem_numero'},
  {'query': 'Praia de Ipanema, Rio de Janeiro, RJ',              'state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'sem_numero'},
  {'query': 'Rua Dias Ferreira, Rio de Janeiro, RJ',             'state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'sem_numero'},
  {'query': 'Rua Visconde de Piraja, Rio de Janeiro, RJ',        'state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'sem_numero'},
  {'query': 'Rua do Ouvidor, Rio de Janeiro, RJ',                'state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'sem_numero'},
  {'query': 'Rua das Flores, Belo Horizonte, MG',                'state_uf': 'MG', 'city': 'Belo Horizonte', 'category': 'sem_numero'},
  {'query': 'Avenida Amazonas, Belo Horizonte, MG',              'state_uf': 'MG', 'city': 'Belo Horizonte', 'category': 'sem_numero'},
  {'query': 'Rua Guajajaras, Belo Horizonte, MG',                'state_uf': 'MG', 'city': 'Belo Horizonte', 'category': 'sem_numero'},
  {'query': 'Rua da Praia, Porto Alegre, RS',                    'state_uf': 'RS', 'city': 'Porto Alegre',   'category': 'sem_numero'},
  {'query': 'Avenida Independência, Porto Alegre, RS',           'state_uf': 'RS', 'city': 'Porto Alegre',   'category': 'sem_numero'},
  {'query': 'Rua Duque de Caxias, Porto Alegre, RS',             'state_uf': 'RS', 'city': 'Porto Alegre',   'category': 'sem_numero'},
  {'query': 'Rua Marechal Floriano, Curitiba, PR',               'state_uf': 'PR', 'city': 'Curitiba',       'category': 'sem_numero'},
  {'query': 'Avenida Marechal Deodoro, Curitiba, PR',            'state_uf': 'PR', 'city': 'Curitiba',       'category': 'sem_numero'},
  {'query': 'Rua Nereu Ramos, Florianópolis, SC',                'state_uf': 'SC', 'city': 'Florianópolis',  'category': 'sem_numero'},
  {'query': 'Avenida Hercílio Luz, Florianópolis, SC',           'state_uf': 'SC', 'city': 'Florianópolis',  'category': 'sem_numero'},
  {'query': 'Rua Carlos Gomes, Florianópolis, SC',               'state_uf': 'SC', 'city': 'Florianópolis',  'category': 'sem_numero'},
  {'query': 'Rua do Carmo, Salvador, BA',                        'state_uf': 'BA', 'city': 'Salvador',       'category': 'sem_numero'},
  {'query': 'Avenida Juracy Magalhães Junior, Salvador, BA',     'state_uf': 'BA', 'city': 'Salvador',       'category': 'sem_numero'},
  {'query': 'Rua do Riachuelo, Recife, PE',                      'state_uf': 'PE', 'city': 'Recife',         'category': 'sem_numero'},
  {'query': 'Rua da Palma, Recife, PE',                          'state_uf': 'PE', 'city': 'Recife',         'category': 'sem_numero'},
  {'query': 'Rua Senador Pompeu, Fortaleza, CE',                 'state_uf': 'CE', 'city': 'Fortaleza',      'category': 'sem_numero'},
  {'query': 'Rua João Moreira, Fortaleza, CE',                   'state_uf': 'CE', 'city': 'Fortaleza',      'category': 'sem_numero'},
  {'query': 'Avenida Sete de Setembro, Manaus, AM',              'state_uf': 'AM', 'city': 'Manaus',         'category': 'sem_numero'},
  {'query': 'Rua Henrique Martins, Manaus, AM',                  'state_uf': 'AM', 'city': 'Manaus',         'category': 'sem_numero'},
  {'query': 'Rua João Balbi, Belém, PA',                         'state_uf': 'PA', 'city': 'Belém',          'category': 'sem_numero'},
  {'query': 'Avenida Presidente Vargas, Belém, PA',              'state_uf': 'PA', 'city': 'Belém',          'category': 'sem_numero'},
  {'query': 'Eixo Monumental, Brasília, DF',                     'state_uf': 'DF', 'city': 'Brasília',       'category': 'sem_numero'},
  {'query': 'Avenida das Nações, Brasília, DF',                  'state_uf': 'DF', 'city': 'Brasília',       'category': 'sem_numero'},
  {'query': 'Rua 68, Goiânia, GO',                               'state_uf': 'GO', 'city': 'Goiânia',        'category': 'sem_numero'},
  {'query': 'Avenida Anhanguera, Goiânia, GO',                   'state_uf': 'GO', 'city': 'Goiânia',        'category': 'sem_numero'},
  {'query': 'Rua Cândido Mariano, Cuiabá, MT',                   'state_uf': 'MT', 'city': 'Cuiabá',         'category': 'sem_numero'},
  {'query': 'Avenida Isaac Póvoas, Cuiabá, MT',                  'state_uf': 'MT', 'city': 'Cuiabá',         'category': 'sem_numero'},
  {'query': 'Rua 14 de Julho, Campo Grande, MS',                 'state_uf': 'MS', 'city': 'Campo Grande',   'category': 'sem_numero'},
  {'query': 'Avenida Fernando Corrêa da Costa, Cuiabá, MT',      'state_uf': 'MT', 'city': 'Cuiabá',         'category': 'sem_numero'},
  {'query': 'Rua Nestor Gomes, Vitória, ES',                     'state_uf': 'ES', 'city': 'Vitória',        'category': 'sem_numero'},
  {'query': 'Rua Saldanha Marinho, São Luís, MA',                'state_uf': 'MA', 'city': 'São Luís',       'category': 'sem_numero'},
  {'query': 'Rua da Paz, Teresina, PI',                          'state_uf': 'PI', 'city': 'Teresina',       'category': 'sem_numero'},
  {'query': 'Rua Apodi, Natal, RN',                              'state_uf': 'RN', 'city': 'Natal',          'category': 'sem_numero'},
  {'query': 'Rua Epitácio Pessoa, João Pessoa, PB',              'state_uf': 'PB', 'city': 'João Pessoa',    'category': 'sem_numero'},
  {'query': 'Rua João Pessoa, Aracaju, SE',                      'state_uf': 'SE', 'city': 'Aracaju',        'category': 'sem_numero'},
  {'query': 'Rua do Sol, Maceió, AL',                            'state_uf': 'AL', 'city': 'Maceió',         'category': 'sem_numero'},
  {'query': 'Quadra 202 Sul, Palmas, TO',                        'state_uf': 'TO', 'city': 'Palmas',         'category': 'sem_numero'},
  {'query': 'Rua Dom Pedro II, Porto Velho, RO',                 'state_uf': 'RO', 'city': 'Porto Velho',    'category': 'sem_numero'},
  {'query': 'Rua Marechal Deodoro, Rio Branco, AC',              'state_uf': 'AC', 'city': 'Rio Branco',     'category': 'sem_numero'},
  {'query': 'Rua Tiradentes, Macapá, AP',                        'state_uf': 'AP', 'city': 'Macapá',         'category': 'sem_numero'},
  {'query': 'Avenida Ville Roy, Boa Vista, RR',                  'state_uf': 'RR', 'city': 'Boa Vista',      'category': 'sem_numero'},
  {'query': 'Rua das Mangabeiras, Campinas, SP',                 'state_uf': 'SP', 'city': 'Campinas',       'category': 'sem_numero'},
  {'query': 'Avenida Norte Sul, Campinas, SP',                   'state_uf': 'SP', 'city': 'Campinas',       'category': 'sem_numero'},
  {'query': 'Rua do Carmo, São Paulo, SP',                       'state_uf': 'SP', 'city': 'São Paulo',      'category': 'sem_numero'},
  {'query': 'Rua Frei Caneca, São Paulo, SP',                    'state_uf': 'SP', 'city': 'São Paulo',      'category': 'sem_numero'},
  {'query': 'Rua São Bento, São Paulo, SP',                      'state_uf': 'SP', 'city': 'São Paulo',      'category': 'sem_numero'},
  {'query': 'Rua Direita, São Paulo, SP',                        'state_uf': 'SP', 'city': 'São Paulo',      'category': 'sem_numero'},
  {'query': 'Alameda Lorena, São Paulo, SP',                     'state_uf': 'SP', 'city': 'São Paulo',      'category': 'sem_numero'},
  {'query': 'Rua Estados Unidos, São Paulo, SP',                 'state_uf': 'SP', 'city': 'São Paulo',      'category': 'sem_numero'},
  {'query': 'Rua Bela Cintra, São Paulo, SP',                    'state_uf': 'SP', 'city': 'São Paulo',      'category': 'sem_numero'},
  {'query': 'Rua Pamplona, São Paulo, SP',                       'state_uf': 'SP', 'city': 'São Paulo',      'category': 'sem_numero'},
  {'query': 'Rua Pedroso, Piracicaba, SP',                       'state_uf': 'SP', 'city': 'Piracicaba',     'category': 'sem_numero'},
  {'query': 'Rua Moraes Barros, Piracicaba, SP',                 'state_uf': 'SP', 'city': 'Piracicaba',     'category': 'sem_numero'},
  {'query': 'Rua Xavier da Silveira, Santos, SP',                'state_uf': 'SP', 'city': 'Santos',         'category': 'sem_numero'},
  {'query': 'Avenida Epitácio Pessoa, Rio de Janeiro, RJ',       'state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'sem_numero'},
  {'query': 'Rua Barão da Torre, Rio de Janeiro, RJ',            'state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'sem_numero'},
  {'query': 'Rua Garcia D\'Ávila, Rio de Janeiro, RJ',           'state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'sem_numero'},
  {'query': 'Avenida Nossa Senhora de Copacabana, Rio de Janeiro, RJ','state_uf':'RJ','city':'Rio de Janeiro','category':'sem_numero'},
  {'query': 'Rua Sergipe, Belo Horizonte, MG',                   'state_uf': 'MG', 'city': 'Belo Horizonte', 'category': 'sem_numero'},
  {'query': 'Rua Tupis, Belo Horizonte, MG',                     'state_uf': 'MG', 'city': 'Belo Horizonte', 'category': 'sem_numero'},
  {'query': 'Rua Gonçalves Dias, Belo Horizonte, MG',            'state_uf': 'MG', 'city': 'Belo Horizonte', 'category': 'sem_numero'},
  {'query': 'Rua Guilherme Schell, Porto Alegre, RS',            'state_uf': 'RS', 'city': 'Porto Alegre',   'category': 'sem_numero'},
  {'query': 'Rua Lima e Silva, Porto Alegre, RS',                'state_uf': 'RS', 'city': 'Porto Alegre',   'category': 'sem_numero'},
  {'query': 'Rua Voluntários da Pátria, Porto Alegre, RS',       'state_uf': 'RS', 'city': 'Porto Alegre',   'category': 'sem_numero'},
  {'query': 'Rua Trajano, Florianópolis, SC',                    'state_uf': 'SC', 'city': 'Florianópolis',  'category': 'sem_numero'},
  {'query': 'Avenida Mauro Ramos, Florianópolis, SC',            'state_uf': 'SC', 'city': 'Florianópolis',  'category': 'sem_numero'},
  {'query': 'Rua Álvaro Otacílio, Florianópolis, SC',            'state_uf': 'SC', 'city': 'Florianópolis',  'category': 'sem_numero'},
  {'query': 'Rua do Passo, Salvador, BA',                        'state_uf': 'BA', 'city': 'Salvador',       'category': 'sem_numero'},
  {'query': 'Rua Gregório de Matos, Salvador, BA',               'state_uf': 'BA', 'city': 'Salvador',       'category': 'sem_numero'},
  {'query': 'Rua da Aurora, Recife, PE',                         'state_uf': 'PE', 'city': 'Recife',         'category': 'sem_numero'},
  {'query': 'Rua Imperial, Recife, PE',                          'state_uf': 'PE', 'city': 'Recife',         'category': 'sem_numero'},
  {'query': 'Rua Liberato Barroso, Fortaleza, CE',               'state_uf': 'CE', 'city': 'Fortaleza',      'category': 'sem_numero'},
  {'query': 'Rua 24 de Maio, Fortaleza, CE',                     'state_uf': 'CE', 'city': 'Fortaleza',      'category': 'sem_numero'},

  // ── cidade_media (100) — cidades que não são capitais de estado ───────────
  {'query': 'Praça Central, Bauru, SP',                          'state_uf': 'SP', 'city': 'Bauru',          'category': 'cidade_media'},
  {'query': 'Rua Araújo Leite, Bauru, SP',                       'state_uf': 'SP', 'city': 'Bauru',          'category': 'cidade_media'},
  {'query': 'Avenida Nações Unidas, Bauru, SP',                  'state_uf': 'SP', 'city': 'Bauru',          'category': 'cidade_media'},
  {'query': 'Rua Floriano Peixoto, Piracicaba, SP',              'state_uf': 'SP', 'city': 'Piracicaba',     'category': 'cidade_media'},
  {'query': 'Avenida Limeira, Piracicaba, SP',                   'state_uf': 'SP', 'city': 'Piracicaba',     'category': 'cidade_media'},
  {'query': 'Rua Prudente de Moraes, Piracicaba, SP',            'state_uf': 'SP', 'city': 'Piracicaba',     'category': 'cidade_media'},
  {'query': 'Rua Dr. Leôncio de Magalhães, Piracicaba, SP',      'state_uf': 'SP', 'city': 'Piracicaba',     'category': 'cidade_media'},
  {'query': 'Rua Rangel Pestana, Piracicaba, SP',                'state_uf': 'SP', 'city': 'Piracicaba',     'category': 'cidade_media'},
  {'query': 'Avenida Dr. Paulo de Morais, Santos, SP',           'state_uf': 'SP', 'city': 'Santos',         'category': 'cidade_media'},
  {'query': 'Rua Amador Bueno, Santos, SP',                      'state_uf': 'SP', 'city': 'Santos',         'category': 'cidade_media'},
  {'query': 'Praia do Gonzaga, Santos, SP',                      'state_uf': 'SP', 'city': 'Santos',         'category': 'cidade_media'},
  {'query': 'Avenida Pedro Lessa, Santos, SP',                   'state_uf': 'SP', 'city': 'Santos',         'category': 'cidade_media'},
  {'query': 'Rua José Menino, Santos, SP',                       'state_uf': 'SP', 'city': 'Santos',         'category': 'cidade_media'},
  {'query': 'Avenida Carlos Grimaldi, Santa Bárbara d\'Oeste, SP','state_uf': 'SP','city': 'Santa Bárbara d\'Oeste','category':'cidade_media'},
  {'query': 'Rua Francisco Glicério, Campinas, SP',              'state_uf': 'SP', 'city': 'Campinas',       'category': 'cidade_media'},
  {'query': 'Avenida Orosimbo Maia, Campinas, SP',               'state_uf': 'SP', 'city': 'Campinas',       'category': 'cidade_media'},
  {'query': 'Rua Barão de Jaguara, Campinas, SP',                'state_uf': 'SP', 'city': 'Campinas',       'category': 'cidade_media'},
  {'query': 'Avenida Brasil, Ribeirão Preto, SP',                'state_uf': 'SP', 'city': 'Ribeirão Preto', 'category': 'cidade_media'},
  {'query': 'Rua Álvares Cabral, Ribeirão Preto, SP',            'state_uf': 'SP', 'city': 'Ribeirão Preto', 'category': 'cidade_media'},
  {'query': 'Rua Duque de Caxias, Sorocaba, SP',                 'state_uf': 'SP', 'city': 'Sorocaba',       'category': 'cidade_media'},
  {'query': 'Avenida Dom Aguirre, Sorocaba, SP',                 'state_uf': 'SP', 'city': 'Sorocaba',       'category': 'cidade_media'},
  {'query': 'Rua Getúlio Vargas, São José do Rio Preto, SP',     'state_uf': 'SP', 'city': 'São José do Rio Preto','category':'cidade_media'},
  {'query': 'Rua Voluntários da Pátria, Taubaté, SP',            'state_uf': 'SP', 'city': 'Taubaté',        'category': 'cidade_media'},
  {'query': 'Avenida Independência, Araçatuba, SP',              'state_uf': 'SP', 'city': 'Araçatuba',      'category': 'cidade_media'},
  {'query': 'Rua Rio Branco, Caxias do Sul, RS',                 'state_uf': 'RS', 'city': 'Caxias do Sul',  'category': 'cidade_media'},
  {'query': 'Avenida Júlio de Castilhos, Caxias do Sul, RS',     'state_uf': 'RS', 'city': 'Caxias do Sul',  'category': 'cidade_media'},
  {'query': 'Rua Sinimbu, Caxias do Sul, RS',                    'state_uf': 'RS', 'city': 'Caxias do Sul',  'category': 'cidade_media'},
  {'query': 'Rua Sepé, Pelotas, RS',                             'state_uf': 'RS', 'city': 'Pelotas',        'category': 'cidade_media'},
  {'query': 'Avenida Bento Gonçalves, Pelotas, RS',              'state_uf': 'RS', 'city': 'Pelotas',        'category': 'cidade_media'},
  {'query': 'Avenida XV de Novembro, Pelotas, RS',               'state_uf': 'RS', 'city': 'Pelotas',        'category': 'cidade_media'},
  {'query': 'Rua das Laranjeiras, Londrina, PR',                 'state_uf': 'PR', 'city': 'Londrina',       'category': 'cidade_media'},
  {'query': 'Avenida Higienópolis, Londrina, PR',                'state_uf': 'PR', 'city': 'Londrina',       'category': 'cidade_media'},
  {'query': 'Rua Pará, Maringá, PR',                             'state_uf': 'PR', 'city': 'Maringá',        'category': 'cidade_media'},
  {'query': 'Avenida Brasil, Maringá, PR',                       'state_uf': 'PR', 'city': 'Maringá',        'category': 'cidade_media'},
  {'query': 'Rua Jorge Lacerda, Foz do Iguaçu, PR',             'state_uf': 'PR', 'city': 'Foz do Iguaçu',  'category': 'cidade_media'},
  {'query': 'Cataratas do Iguaçu, Foz do Iguaçu, PR',           'state_uf': 'PR', 'city': 'Foz do Iguaçu',  'category': 'cidade_media'},
  {'query': 'Rua Victor Konder, Blumenau, SC',                   'state_uf': 'SC', 'city': 'Blumenau',       'category': 'cidade_media'},
  {'query': 'Avenida Brasil, Blumenau, SC',                      'state_uf': 'SC', 'city': 'Blumenau',       'category': 'cidade_media'},
  {'query': 'Rua XV de Novembro, Joinville, SC',                 'state_uf': 'SC', 'city': 'Joinville',      'category': 'cidade_media'},
  {'query': 'Rua Princesa Isabel, Joinville, SC',                'state_uf': 'SC', 'city': 'Joinville',      'category': 'cidade_media'},
  {'query': 'Avenida Senhor do Bonfim, Feira de Santana, BA',    'state_uf': 'BA', 'city': 'Feira de Santana','category':'cidade_media'},
  {'query': 'Rua Marechal Deodoro, Vitória da Conquista, BA',    'state_uf': 'BA', 'city': 'Vitória da Conquista','category':'cidade_media'},
  {'query': 'Rua Vidal de Negreiros, Caruaru, PE',               'state_uf': 'PE', 'city': 'Caruaru',        'category': 'cidade_media'},
  {'query': 'Rua Treze de Maio, Juazeiro do Norte, CE',          'state_uf': 'CE', 'city': 'Juazeiro do Norte','category':'cidade_media'},
  {'query': 'Rua São Pedro, Sobral, CE',                         'state_uf': 'CE', 'city': 'Sobral',         'category': 'cidade_media'},
  {'query': 'Rua do Comércio, Mossoró, RN',                      'state_uf': 'RN', 'city': 'Mossoró',        'category': 'cidade_media'},
  {'query': 'Rua Seridó, Campina Grande, PB',                    'state_uf': 'PB', 'city': 'Campina Grande', 'category': 'cidade_media'},
  {'query': 'Rua Marquês de Aracati, Campina Grande, PB',        'state_uf': 'PB', 'city': 'Campina Grande', 'category': 'cidade_media'},
  {'query': 'Rua João Tavares, Nossa Senhora do Socorro, SE',    'state_uf': 'SE', 'city': 'Nossa Senhora do Socorro','category':'cidade_media'},
  {'query': 'Rua Barão de Penedo, Arapiraca, AL',                'state_uf': 'AL', 'city': 'Arapiraca',      'category': 'cidade_media'},
  {'query': 'Rua do Açaí, Imperatriz, MA',                       'state_uf': 'MA', 'city': 'Imperatriz',     'category': 'cidade_media'},
  {'query': 'Rua das Mangueiras, Parnaíba, PI',                  'state_uf': 'PI', 'city': 'Parnaíba',       'category': 'cidade_media'},
  {'query': 'Rua do Comercio, Anápolis, GO',                     'state_uf': 'GO', 'city': 'Anápolis',       'category': 'cidade_media'},
  {'query': 'Avenida Brasil Sul, Anápolis, GO',                  'state_uf': 'GO', 'city': 'Anápolis',       'category': 'cidade_media'},
  {'query': 'Rua XV de Novembro, Rio Verde, GO',                 'state_uf': 'GO', 'city': 'Rio Verde',      'category': 'cidade_media'},
  {'query': 'Rua Goiás, Rondonópolis, MT',                       'state_uf': 'MT', 'city': 'Rondonópolis',   'category': 'cidade_media'},
  {'query': 'Rua das Acácias, Várzea Grande, MT',                'state_uf': 'MT', 'city': 'Várzea Grande',  'category': 'cidade_media'},
  {'query': 'Rua Três de Outubro, Dourados, MS',                 'state_uf': 'MS', 'city': 'Dourados',       'category': 'cidade_media'},
  {'query': 'Rua Rio Brilhante, Três Lagoas, MS',                'state_uf': 'MS', 'city': 'Três Lagoas',    'category': 'cidade_media'},
  {'query': 'Rua Guilherme Santos Neves, Cachoeiro de Itapemirim, ES','state_uf':'ES','city':'Cachoeiro de Itapemirim','category':'cidade_media'},
  {'query': 'Rua Coronel Verdun, São Carlos, SP',                'state_uf': 'SP', 'city': 'São Carlos',     'category': 'cidade_media'},
  {'query': 'Avenida São Carlos, São Carlos, SP',                'state_uf': 'SP', 'city': 'São Carlos',     'category': 'cidade_media'},
  {'query': 'Rua Major José Levy Sobrinho, Limeira, SP',         'state_uf': 'SP', 'city': 'Limeira',        'category': 'cidade_media'},
  {'query': 'Rua Barão de Jaguara, Limeira, SP',                 'state_uf': 'SP', 'city': 'Limeira',        'category': 'cidade_media'},
  {'query': 'Rua Duque de Caxias, Americana, SP',                'state_uf': 'SP', 'city': 'Americana',      'category': 'cidade_media'},
  {'query': 'Avenida Brasil, Americana, SP',                     'state_uf': 'SP', 'city': 'Americana',      'category': 'cidade_media'},
  {'query': 'Rua Esteves Júnior, Florianópolis, SC',             'state_uf': 'SC', 'city': 'Florianópolis',  'category': 'cidade_media'},
  {'query': 'Avenida das Torres, Palhoça, SC',                   'state_uf': 'SC', 'city': 'Palhoça',        'category': 'cidade_media'},
  {'query': 'Rua Coronel Marcos, São Bernardo do Campo, SP',     'state_uf': 'SP', 'city': 'São Bernardo do Campo','category':'cidade_media'},
  {'query': 'Avenida Kennedy, São Bernardo do Campo, SP',        'state_uf': 'SP', 'city': 'São Bernardo do Campo','category':'cidade_media'},
  {'query': 'Rua Tabapuã, Santo André, SP',                      'state_uf': 'SP', 'city': 'Santo André',    'category': 'cidade_media'},
  {'query': 'Avenida Industrial, Santo André, SP',               'state_uf': 'SP', 'city': 'Santo André',    'category': 'cidade_media'},
  {'query': 'Rua Sete de Setembro, São José dos Campos, SP',     'state_uf': 'SP', 'city': 'São José dos Campos','category':'cidade_media'},
  {'query': 'Avenida Adhemar de Barros, Araraquara, SP',         'state_uf': 'SP', 'city': 'Araraquara',     'category': 'cidade_media'},
  {'query': 'Rua Rui Barbosa, Franca, SP',                       'state_uf': 'SP', 'city': 'Franca',         'category': 'cidade_media'},
  {'query': 'Avenida Major Nicácio, Franca, SP',                 'state_uf': 'SP', 'city': 'Franca',         'category': 'cidade_media'},
  {'query': 'Rua Marechal Floriano Peixoto, Presidente Prudente, SP','state_uf':'SP','city':'Presidente Prudente','category':'cidade_media'},
  {'query': 'Rua Coronel Marcondes, Presidente Prudente, SP',    'state_uf': 'SP', 'city': 'Presidente Prudente','category':'cidade_media'},
  {'query': 'Rua Pedro Ometto, Lençóis Paulista, SP',            'state_uf': 'SP', 'city': 'Lençóis Paulista','category':'cidade_media'},
  {'query': 'Rua Padre Anchieta, Botucatu, SP',                  'state_uf': 'SP', 'city': 'Botucatu',       'category': 'cidade_media'},
  {'query': 'Avenida Vital Brasil, Botucatu, SP',                'state_uf': 'SP', 'city': 'Botucatu',       'category': 'cidade_media'},
  {'query': 'Rua Estrada de Ferro, Jundiaí, SP',                 'state_uf': 'SP', 'city': 'Jundiaí',        'category': 'cidade_media'},
  {'query': 'Avenida União dos Ferroviários, Jundiaí, SP',       'state_uf': 'SP', 'city': 'Jundiaí',        'category': 'cidade_media'},
  {'query': 'Rua Santa Rosa, Itu, SP',                           'state_uf': 'SP', 'city': 'Itu',            'category': 'cidade_media'},
  {'query': 'Rua Padre Anchieta, Itu, SP',                       'state_uf': 'SP', 'city': 'Itu',            'category': 'cidade_media'},
  {'query': 'Rua Coronel Ordine, Guaratinguetá, SP',             'state_uf': 'SP', 'city': 'Guaratinguetá',  'category': 'cidade_media'},
  {'query': 'Rua Onze de Agosto, Mogi das Cruzes, SP',           'state_uf': 'SP', 'city': 'Mogi das Cruzes','category':'cidade_media'},
  {'query': 'Avenida Cívica, Mogi das Cruzes, SP',               'state_uf': 'SP', 'city': 'Mogi das Cruzes','category':'cidade_media'},
  {'query': 'Rua Dom Nery, Poços de Caldas, MG',                 'state_uf': 'MG', 'city': 'Poços de Caldas','category':'cidade_media'},
  {'query': 'Rua João Pinheiro, Uberlândia, MG',                 'state_uf': 'MG', 'city': 'Uberlândia',     'category': 'cidade_media'},
  {'query': 'Avenida João Naves de Ávila, Uberlândia, MG',       'state_uf': 'MG', 'city': 'Uberlândia',     'category': 'cidade_media'},

  // ── com_acento (50) — endereços com acentos e caracteres especiais ─────────
  {'query': 'Praça da República, São Paulo, SP',                 'state_uf': 'SP', 'city': 'São Paulo',      'category': 'com_acento'},
  {'query': 'Avenida São João, São Paulo, SP',                   'state_uf': 'SP', 'city': 'São Paulo',      'category': 'com_acento'},
  {'query': 'Rua Líbero Badaró, São Paulo, SP',                  'state_uf': 'SP', 'city': 'São Paulo',      'category': 'com_acento'},
  {'query': 'Praça da Sé, São Paulo, SP',                        'state_uf': 'SP', 'city': 'São Paulo',      'category': 'com_acento'},
  {'query': 'Rua Álvares Penteado, São Paulo, SP',               'state_uf': 'SP', 'city': 'São Paulo',      'category': 'com_acento'},
  {'query': 'Avenida Angélica, São Paulo, SP',                   'state_uf': 'SP', 'city': 'São Paulo',      'category': 'com_acento'},
  {'query': 'Praça da Liberdade, São Paulo, SP',                 'state_uf': 'SP', 'city': 'São Paulo',      'category': 'com_acento'},
  {'query': 'Rua José Getúlio, São Paulo, SP',                   'state_uf': 'SP', 'city': 'São Paulo',      'category': 'com_acento'},
  {'query': 'Rua Barão de Itapetininga, São Paulo, SP',          'state_uf': 'SP', 'city': 'São Paulo',      'category': 'com_acento'},
  {'query': 'Rua Jóquei Clube, Piracicaba, SP',                  'state_uf': 'SP', 'city': 'Piracicaba',     'category': 'com_acento'},
  {'query': 'Rua João Lúcio de Azevedo, Piracicaba, SP',         'state_uf': 'SP', 'city': 'Piracicaba',     'category': 'com_acento'},
  {'query': 'Praça José Bonifácio, Piracicaba, SP',              'state_uf': 'SP', 'city': 'Piracicaba',     'category': 'com_acento'},
  {'query': 'Rua Irmã Lúcia, Santos, SP',                        'state_uf': 'SP', 'city': 'Santos',         'category': 'com_acento'},
  {'query': 'Praça dos Andradas, Santos, SP',                    'state_uf': 'SP', 'city': 'Santos',         'category': 'com_acento'},
  {'query': 'Rua Cônego Januário, Santos, SP',                   'state_uf': 'SP', 'city': 'Santos',         'category': 'com_acento'},
  {'query': 'Praça Tiradentes, Ouro Preto, MG',                  'state_uf': 'MG', 'city': 'Ouro Preto',     'category': 'com_acento'},
  {'query': 'Rua São José, Ouro Preto, MG',                      'state_uf': 'MG', 'city': 'Ouro Preto',     'category': 'com_acento'},
  {'query': 'Rua Direita, Ouro Preto, MG',                       'state_uf': 'MG', 'city': 'Ouro Preto',     'category': 'com_acento'},
  {'query': 'Praça da Liberdade, Belo Horizonte, MG',            'state_uf': 'MG', 'city': 'Belo Horizonte', 'category': 'com_acento'},
  {'query': 'Rua Inácio de Azambuja, Porto Alegre, RS',          'state_uf': 'RS', 'city': 'Porto Alegre',   'category': 'com_acento'},
  {'query': 'Praça XV de Novembro, Florianópolis, SC',           'state_uf': 'SC', 'city': 'Florianópolis',  'category': 'com_acento'},
  {'query': 'Rua Cônsul Carlos Renaux, Brusque, SC',             'state_uf': 'SC', 'city': 'Brusque',        'category': 'com_acento'},
  {'query': 'Ladeira da Barra, Salvador, BA',                    'state_uf': 'BA', 'city': 'Salvador',       'category': 'com_acento'},
  {'query': 'Praça da Sé, Salvador, BA',                         'state_uf': 'BA', 'city': 'Salvador',       'category': 'com_acento'},
  {'query': 'Rua João Pondé, Salvador, BA',                      'state_uf': 'BA', 'city': 'Salvador',       'category': 'com_acento'},
  {'query': 'Rua Dom Malan, Petrolina, PE',                      'state_uf': 'PE', 'city': 'Petrolina',      'category': 'com_acento'},
  {'query': 'Praça Sete de Setembro, Fortaleza, CE',             'state_uf': 'CE', 'city': 'Fortaleza',      'category': 'com_acento'},
  {'query': 'Rua Ótávio Bonfim, Sobral, CE',                     'state_uf': 'CE', 'city': 'Sobral',         'category': 'com_acento'},
  {'query': 'Rua Sílvio Leite, Natal, RN',                       'state_uf': 'RN', 'city': 'Natal',          'category': 'com_acento'},
  {'query': 'Rua Afonso Pena, João Pessoa, PB',                  'state_uf': 'PB', 'city': 'João Pessoa',    'category': 'com_acento'},
  {'query': 'Praça Fausto Cardoso, Aracaju, SE',                 'state_uf': 'SE', 'city': 'Aracaju',        'category': 'com_acento'},
  {'query': 'Rua João Pessoa, Maceió, AL',                       'state_uf': 'AL', 'city': 'Maceió',         'category': 'com_acento'},
  {'query': 'Praça Deodoro, Maceió, AL',                         'state_uf': 'AL', 'city': 'Maceió',         'category': 'com_acento'},
  {'query': 'Rua José Nascimento, São Luís, MA',                 'state_uf': 'MA', 'city': 'São Luís',       'category': 'com_acento'},
  {'query': 'Rua Álvaro Mendes, Teresina, PI',                   'state_uf': 'PI', 'city': 'Teresina',       'category': 'com_acento'},
  {'query': 'Praça Cívica, Goiânia, GO',                         'state_uf': 'GO', 'city': 'Goiânia',        'category': 'com_acento'},
  {'query': 'Rua Getúlio Vargas, Goiânia, GO',                   'state_uf': 'GO', 'city': 'Goiânia',        'category': 'com_acento'},
  {'query': 'Rua Antônio Maria Coelho, Campo Grande, MS',        'state_uf': 'MS', 'city': 'Campo Grande',   'category': 'com_acento'},
  {'query': 'Avenida Mato Grosso, Campo Grande, MS',             'state_uf': 'MS', 'city': 'Campo Grande',   'category': 'com_acento'},
  {'query': 'Rua Barão do Rio Branco, Cuiabá, MT',               'state_uf': 'MT', 'city': 'Cuiabá',         'category': 'com_acento'},
  {'query': 'Praça da República, Belém, PA',                     'state_uf': 'PA', 'city': 'Belém',          'category': 'com_acento'},
  {'query': 'Rua João Alfredo, Belém, PA',                       'state_uf': 'PA', 'city': 'Belém',          'category': 'com_acento'},
  {'query': 'Avenida Getúlio Vargas, Manaus, AM',                'state_uf': 'AM', 'city': 'Manaus',         'category': 'com_acento'},
  {'query': 'Rua Bernardo Ramos, Manaus, AM',                    'state_uf': 'AM', 'city': 'Manaus',         'category': 'com_acento'},
  {'query': 'Setor Hoteleiro Sul, Brasília, DF',                 'state_uf': 'DF', 'city': 'Brasília',       'category': 'com_acento'},
  {'query': 'Esplanada dos Ministérios, Brasília, DF',           'state_uf': 'DF', 'city': 'Brasília',       'category': 'com_acento'},
  {'query': 'Rua João Negrão, Curitiba, PR',                     'state_uf': 'PR', 'city': 'Curitiba',       'category': 'com_acento'},
  {'query': 'Praça Tiradentes, Curitiba, PR',                    'state_uf': 'PR', 'city': 'Curitiba',       'category': 'com_acento'},
  {'query': 'Rua Barão de Cotegipe, Vitória, ES',                'state_uf': 'ES', 'city': 'Vitória',        'category': 'com_acento'},
  {'query': 'Rua José de Anchieta, Rio Branco, AC',              'state_uf': 'AC', 'city': 'Rio Branco',     'category': 'com_acento'},
  {'query': 'Rua São Sebastião, Macapá, AP',                     'state_uf': 'AP', 'city': 'Macapá',         'category': 'com_acento'},

  // ── ambiguo (50) — ruas que existem em múltiplas cidades ──────────────────
  {'query': 'Rua das Flores, São Paulo, SP',                     'state_uf': 'SP', 'city': 'São Paulo',      'category': 'ambiguo'},
  {'query': 'Rua das Flores, Rio de Janeiro, RJ',                'state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'ambiguo'},
  {'query': 'Rua das Flores, Belo Horizonte, MG',                'state_uf': 'MG', 'city': 'Belo Horizonte', 'category': 'ambiguo'},
  {'query': 'Rua das Flores, Curitiba, PR',                      'state_uf': 'PR', 'city': 'Curitiba',       'category': 'ambiguo'},
  {'query': 'Rua das Flores, Porto Alegre, RS',                  'state_uf': 'RS', 'city': 'Porto Alegre',   'category': 'ambiguo'},
  {'query': 'Avenida Brasil, São Paulo, SP',                     'state_uf': 'SP', 'city': 'São Paulo',      'category': 'ambiguo'},
  {'query': 'Avenida Brasil, Rio de Janeiro, RJ',                'state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'ambiguo'},
  {'query': 'Avenida Brasil, Recife, PE',                        'state_uf': 'PE', 'city': 'Recife',         'category': 'ambiguo'},
  {'query': 'Avenida Brasil, Manaus, AM',                        'state_uf': 'AM', 'city': 'Manaus',         'category': 'ambiguo'},
  {'query': 'Avenida Brasil, Belém, PA',                         'state_uf': 'PA', 'city': 'Belém',          'category': 'ambiguo'},
  {'query': 'Rua XV de Novembro, São Paulo, SP',                 'state_uf': 'SP', 'city': 'São Paulo',      'category': 'ambiguo'},
  {'query': 'Rua XV de Novembro, Curitiba, PR',                  'state_uf': 'PR', 'city': 'Curitiba',       'category': 'ambiguo'},
  {'query': 'Rua XV de Novembro, Florianópolis, SC',             'state_uf': 'SC', 'city': 'Florianópolis',  'category': 'ambiguo'},
  {'query': 'Rua XV de Novembro, Campinas, SP',                  'state_uf': 'SP', 'city': 'Campinas',       'category': 'ambiguo'},
  {'query': 'Rua XV de Novembro, Santos, SP',                    'state_uf': 'SP', 'city': 'Santos',         'category': 'ambiguo'},
  {'query': 'Rua Sete de Setembro, São Paulo, SP',               'state_uf': 'SP', 'city': 'São Paulo',      'category': 'ambiguo'},
  {'query': 'Rua Sete de Setembro, Rio de Janeiro, RJ',          'state_uf': 'RJ', 'city': 'Rio de Janeiro', 'category': 'ambiguo'},
  {'query': 'Rua Sete de Setembro, Curitiba, PR',                'state_uf': 'PR', 'city': 'Curitiba',       'category': 'ambiguo'},
  {'query': 'Rua Sete de Setembro, Porto Alegre, RS',            'state_uf': 'RS', 'city': 'Porto Alegre',   'category': 'ambiguo'},
  {'query': 'Rua Sete de Setembro, Campinas, SP',                'state_uf': 'SP', 'city': 'Campinas',       'category': 'ambiguo'},
  {'query': 'Rua Tiradentes, São Paulo, SP',                     'state_uf': 'SP', 'city': 'São Paulo',      'category': 'ambiguo'},
  {'query': 'Rua Tiradentes, Curitiba, PR',                      'state_uf': 'PR', 'city': 'Curitiba',       'category': 'ambiguo'},
  {'query': 'Rua Tiradentes, Maceió, AL',                        'state_uf': 'AL', 'city': 'Maceió',         'category': 'ambiguo'},
  {'query': 'Rua Tiradentes, Piracicaba, SP',                    'state_uf': 'SP', 'city': 'Piracicaba',     'category': 'ambiguo'},
  {'query': 'Rua Tiradentes, Campinas, SP',                      'state_uf': 'SP', 'city': 'Campinas',       'category': 'ambiguo'},
  {'query': 'Rua Dom Pedro II, São Paulo, SP',                   'state_uf': 'SP', 'city': 'São Paulo',      'category': 'ambiguo'},
  {'query': 'Rua Dom Pedro II, Campinas, SP',                    'state_uf': 'SP', 'city': 'Campinas',       'category': 'ambiguo'},
  {'query': 'Rua Dom Pedro II, Cuiabá, MT',                      'state_uf': 'MT', 'city': 'Cuiabá',         'category': 'ambiguo'},
  {'query': 'Rua Dom Pedro II, Manaus, AM',                      'state_uf': 'AM', 'city': 'Manaus',         'category': 'ambiguo'},
  {'query': 'Rua Dom Pedro II, Belém, PA',                       'state_uf': 'PA', 'city': 'Belém',          'category': 'ambiguo'},
  {'query': 'Avenida Getúlio Vargas, São Paulo, SP',             'state_uf': 'SP', 'city': 'São Paulo',      'category': 'ambiguo'},
  {'query': 'Avenida Getúlio Vargas, Belo Horizonte, MG',        'state_uf': 'MG', 'city': 'Belo Horizonte', 'category': 'ambiguo'},
  {'query': 'Avenida Getúlio Vargas, Porto Alegre, RS',          'state_uf': 'RS', 'city': 'Porto Alegre',   'category': 'ambiguo'},
  {'query': 'Avenida Getúlio Vargas, Fortaleza, CE',             'state_uf': 'CE', 'city': 'Fortaleza',      'category': 'ambiguo'},
  {'query': 'Avenida Getúlio Vargas, Recife, PE',                'state_uf': 'PE', 'city': 'Recife',         'category': 'ambiguo'},
  {'query': 'Rua João Pessoa, São Paulo, SP',                    'state_uf': 'SP', 'city': 'São Paulo',      'category': 'ambiguo'},
  {'query': 'Rua João Pessoa, Fortaleza, CE',                    'state_uf': 'CE', 'city': 'Fortaleza',      'category': 'ambiguo'},
  {'query': 'Rua João Pessoa, Campo Grande, MS',                 'state_uf': 'MS', 'city': 'Campo Grande',   'category': 'ambiguo'},
  {'query': 'Rua João Pessoa, Natal, RN',                        'state_uf': 'RN', 'city': 'Natal',          'category': 'ambiguo'},
  {'query': 'Rua João Pessoa, Campinas, SP',                     'state_uf': 'SP', 'city': 'Campinas',       'category': 'ambiguo'},
  {'query': 'Rua 13 de Maio, São Paulo, SP',                     'state_uf': 'SP', 'city': 'São Paulo',      'category': 'ambiguo'},
  {'query': 'Rua 13 de Maio, Campinas, SP',                      'state_uf': 'SP', 'city': 'Campinas',       'category': 'ambiguo'},
  {'query': 'Rua 13 de Maio, Santos, SP',                        'state_uf': 'SP', 'city': 'Santos',         'category': 'ambiguo'},
  {'query': 'Rua 13 de Maio, Recife, PE',                        'state_uf': 'PE', 'city': 'Recife',         'category': 'ambiguo'},
  {'query': 'Rua 13 de Maio, Fortaleza, CE',                     'state_uf': 'CE', 'city': 'Fortaleza',      'category': 'ambiguo'},
  {'query': 'Rua Independência, São Paulo, SP',                  'state_uf': 'SP', 'city': 'São Paulo',      'category': 'ambiguo'},
  {'query': 'Rua Independência, Porto Alegre, RS',               'state_uf': 'RS', 'city': 'Porto Alegre',   'category': 'ambiguo'},
  {'query': 'Rua Independência, Fortaleza, CE',                  'state_uf': 'CE', 'city': 'Fortaleza',      'category': 'ambiguo'},
  {'query': 'Rua Independência, Manaus, AM',                     'state_uf': 'AM', 'city': 'Manaus',         'category': 'ambiguo'},
  {'query': 'Rua Independência, Campinas, SP',                   'state_uf': 'SP', 'city': 'Campinas',       'category': 'ambiguo'},
  {'query': 'Rua Independência, Piracicaba, SP',                 'state_uf': 'SP', 'city': 'Piracicaba',     'category': 'ambiguo'},
];

// ─── Widget principal ─────────────────────────────────────────────────────────
class GeocoderBenchmarkScreen extends StatefulWidget {
  const GeocoderBenchmarkScreen({super.key});

  @override
  State<GeocoderBenchmarkScreen> createState() =>
      _GeocoderBenchmarkScreenState();
}

class _GeocoderBenchmarkScreenState extends State<GeocoderBenchmarkScreen> {
  bool _isRunning = false;
  final List<Map<String, dynamic>> _results = [];
  int _current = 0;
  final int _total = _addresses.length;
  final _manualController = TextEditingController();
  String? _manualResult;
  bool _exportDone = false;

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  // Chama o Geocoder nativo para um único endereço.
  Future<Map<String, dynamic>> _searchOne(String query) async {
    try {
      final raw = await _channel.invokeMethod<Map>('searchAddress', {'query': query});
      return Map<String, dynamic>.from(raw ?? {});
    } catch (_) {
      return {'found': false, 'lat': 0.0, 'lon': 0.0, 'returned_address': '', 'has_number': false, 'duration_ms': 0};
    }
  }

  // Roda o loop completo de 500 endereços com delay de 150ms entre chamadas.
  Future<void> _runBenchmark() async {
    setState(() {
      _isRunning = true;
      _results.clear();
      _current = 0;
      _exportDone = false;
    });

    for (final addr in _addresses) {
      if (!mounted) return;
      final geo = await _searchOne(addr['query']!);
      final entry = {
        'query':            addr['query']!,
        'state_uf':         addr['state_uf']!,
        'city':             addr['city']!,
        'category':         addr['category']!,
        'found':            geo['found'] as bool? ?? false,
        'has_number':       geo['has_number'] as bool? ?? false,
        'returned_address': geo['returned_address'] as String? ?? '',
        'lat':              geo['lat'] as double? ?? 0.0,
        'lon':              geo['lon'] as double? ?? 0.0,
        'duration_ms':      geo['duration_ms'] as int? ?? 0,
      };
      setState(() {
        _results.add(entry);
        _current++;
      });
      // Delay entre chamadas para não sobrecarregar o Geocoder do sistema
      await Future.delayed(const Duration(milliseconds: 150));
    }

    await _exportToSupabase();
    if (mounted) setState(() => _isRunning = false);
  }

  // Exporta todos os resultados para o Supabase em lotes de 50.
  Future<void> _exportToSupabase() async {
    const batchSize = 50;
    for (var i = 0; i < _results.length; i += batchSize) {
      final batch = _results.sublist(
        i,
        i + batchSize > _results.length ? _results.length : i + batchSize,
      );
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 10);
        final req = await client.postUrl(Uri.parse(_supabaseUrl));
        req.headers
          ..set('apikey', _supabaseKey)
          ..set('Authorization', 'Bearer $_supabaseKey')
          ..contentType = ContentType.json
          ..set('Prefer', 'return=minimal');
        final body = jsonEncode(batch);
        req.contentLength = utf8.encode(body).length;
        req.write(body);
        final resp = await req.close();
        await resp.drain<void>();
        client.close();
      } catch (_) {
        // Ignora erros de rede — dados ficam disponíveis localmente em _results
      }
    }
    if (mounted) setState(() => _exportDone = true);
  }

  // Teste manual de um único endereço.
  Future<void> _testManual() async {
    final q = _manualController.text.trim();
    if (q.isEmpty) return;
    setState(() => _manualResult = 'Buscando...');
    final geo = await _searchOne(q);
    setState(() {
      _manualResult = geo['found'] == true
          ? 'Encontrado: ${geo['returned_address']}\nLat: ${(geo['lat'] as double).toStringAsFixed(5)} / Lon: ${(geo['lon'] as double).toStringAsFixed(5)}\nTempo: ${geo['duration_ms']} ms'
          : 'Não encontrado (${geo['duration_ms']} ms)';
    });
  }

  // ── UI ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        title: const Text('Benchmark Geocoder'),
        backgroundColor: const Color(0xFF1A1A2E),
      ),
      body: _isRunning ? _buildRunningView() : _buildIdleView(),
    );
  }

  Widget _buildIdleView() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        // ── Botão de início ────────────────────────────────────────────────
        ElevatedButton.icon(
          onPressed: _runBenchmark,
          icon: const Icon(Icons.play_arrow),
          label: Text('Iniciar Bateria ($_total endereços)'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.gap14),
          ),
        ),

        const SizedBox(height: AppSpacing.xl),

        // ── Teste manual ───────────────────────────────────────────────────
        const Text(
          'Teste manual',
          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _manualController,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Ex: Av. Paulista, 1578, São Paulo, SP',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF1A1A2E),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          ),
          onSubmitted: (_) => _testManual(),
        ),
        const SizedBox(height: AppSpacing.xs),
        OutlinedButton(
          onPressed: _testManual,
          child: const Text('Testar endereço'),
        ),
        if (_manualResult != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(
              _manualResult!,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],

        // ── Card de resumo após benchmark completo ─────────────────────────
        if (_results.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          _buildSummaryCard(),
        ],
      ],
    );
  }

  Widget _buildRunningView() {
    final progress = _total > 0 ? _current / _total : 0.0;
    // Últimos 10 resultados para exibição em tempo real
    final recent = _results.length > 10
        ? _results.sublist(_results.length - 10)
        : List.of(_results);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$_current / $_total',
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.xs),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: const Color(0xFF1A1A2E),
                color: Colors.orange,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            itemCount: recent.length,
            itemBuilder: (_, i) => _buildResultTile(recent[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildResultTile(Map<String, dynamic> r) {
    // Verde = encontrado com número, Amarelo = encontrado sem número, Vermelho = não encontrado
    final Color color;
    if (r['found'] == true && r['has_number'] == true) {
      color = Colors.green;
    } else if (r['found'] == true) {
      color = Colors.amber;
    } else {
      color = Colors.redAccent;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              r['query'] as String,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${r['duration_ms']} ms',
            style: TextStyle(color: color, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final total   = _results.length;
    final found   = _results.where((r) => r['found'] == true).length;
    final withNum = _results.where((r) => r['has_number'] == true).length;
    final avgMs   = total > 0
        ? (_results.fold<int>(0, (s, r) => s + (r['duration_ms'] as int)) / total)
            .round()
        : 0;
    final rate    = total > 0 ? (found / total * 100).toStringAsFixed(1) : '0';
    final numRate = found > 0 ? (withNum / found * 100).toStringAsFixed(1) : '0';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(AppRadius.icon),
        border: Border.all(color: Colors.orange.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumo',
            style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.w700,
                fontSize: 15),
          ),
          const SizedBox(height: AppSpacing.sm),
          _summaryRow('Total testados', '$total'),
          _summaryRow('Encontrados', '$found / $total ($rate%)'),
          _summaryRow('Com número', '$withNum ($numRate% dos encontrados)'),
          _summaryRow('Tempo médio', '$avgMs ms'),
          if (_exportDone)
            _summaryRow('Supabase', 'Dados exportados'),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(
                'https://supabase.com/dashboard/project/zqgkfqenrljtncoecegv/editor',
              ),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Ver no Supabase'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ],
      ),
    );
  }
}
